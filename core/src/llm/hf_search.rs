//! HuggingFace GGUF model search — REST API with 5-minute in-memory cache.
//!
//! # Usage
//!
//! ```no_run
//! use libnclaw::llm::hf_search::{search_hf, HfSearchParams};
//!
//! # tokio_test::block_on(async {
//! let results = search_hf(HfSearchParams {
//!     query: "llama-3".into(),
//!     limit: 20,
//! }).await.unwrap();
//! # });
//! ```

use serde::{Deserialize, Serialize};
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Parameters for a HuggingFace GGUF model search.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HfSearchParams {
    /// Free-text search query (e.g. "mistral 7b q4").
    pub query: String,
    /// Maximum number of results to return (1-50, clamped server-side at 50).
    pub limit: u32,
}

/// A single HuggingFace model entry returned by the search API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HfModel {
    /// Full repository ID, e.g. `"bartowski/Meta-Llama-3-8B-Instruct-GGUF"`.
    pub id: String,
    /// Human-readable display name derived from the repo ID (last path segment).
    pub name: String,
    /// Total downloads across all files.
    pub downloads: u64,
    /// Number of GitHub-style likes.
    pub likes: u64,
    /// GGUF file variants available in this repository, if known.
    pub gguf_files: Vec<HfGgufFile>,
}

/// A single GGUF file within a HuggingFace repository.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HfGgufFile {
    /// Filename, e.g. `"Meta-Llama-3-8B-Instruct-Q4_K_M.gguf"`.
    pub filename: String,
    /// File size in bytes (`None` when the API does not report it).
    pub size_bytes: Option<u64>,
    /// Quantisation tag extracted from the filename (e.g. `"Q4_K_M"`).
    pub quant: Option<String>,
}

// ---------------------------------------------------------------------------
// Internal cache
// ---------------------------------------------------------------------------

/// Cache entry: search results + the instant they were populated.
struct CacheEntry {
    params: String, // JSON-serialised HfSearchParams used as key
    results: Vec<HfModel>,
    fetched_at: Instant,
}

/// 5-minute TTL for all HF API responses.
const CACHE_TTL: Duration = Duration::from_secs(300);

/// Process-global cache, lazily initialised.
fn cache() -> &'static RwLock<Vec<CacheEntry>> {
    static CACHE: OnceLock<RwLock<Vec<CacheEntry>>> = OnceLock::new();
    CACHE.get_or_init(|| RwLock::new(Vec::new()))
}

/// Cache key — a deterministic string from the search params.
fn cache_key(params: &HfSearchParams) -> String {
    format!("q={}|limit={}", params.query.trim().to_lowercase(), params.limit)
}

// ---------------------------------------------------------------------------
// HuggingFace API helpers
// ---------------------------------------------------------------------------

/// Raw response shape from `GET /api/models`.
#[derive(Debug, Deserialize)]
struct HfApiModel {
    #[serde(rename = "modelId")]
    model_id: String,
    #[serde(default)]
    downloads: u64,
    #[serde(default)]
    likes: u64,
    #[serde(default)]
    siblings: Vec<HfSibling>,
}

#[derive(Debug, Deserialize)]
struct HfSibling {
    #[serde(rename = "rfilename")]
    rfilename: String,
    // HF's /api/models endpoint does not include file sizes in the sibling list.
    // Size is available via /api/models/{repo}/tree but we skip that call to
    // avoid N+1 requests per search. Size is populated by the downloader when
    // it fetches the resolved blob URL.
    #[serde(rename = "size", default)]
    size: Option<u64>,
}

/// Extract quantisation tag from a GGUF filename.
///
/// Examples:
/// - `"model-Q4_K_M.gguf"` → `Some("Q4_K_M")`
/// - `"model.gguf"` → `None`
fn extract_quant(filename: &str) -> Option<String> {
    // Strip .gguf extension, then look for the last `-`-separated segment that
    // looks like a quant identifier (upper-case, digits, underscores).
    let stem = filename.strip_suffix(".gguf")?;
    stem.rsplit('-').find(|seg| {
        !seg.is_empty()
            && seg.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
            && seg.chars().any(|c| c.is_ascii_alphabetic())
    }).map(|s| s.to_owned())
}

/// Convert a raw API model into the public `HfModel` type.
fn map_model(raw: HfApiModel) -> HfModel {
    let name = raw
        .model_id
        .split('/')
        .last()
        .unwrap_or(&raw.model_id)
        .to_owned();

    let gguf_files = raw
        .siblings
        .into_iter()
        .filter(|s| s.rfilename.ends_with(".gguf"))
        .map(|s| HfGgufFile {
            quant: extract_quant(&s.rfilename),
            size_bytes: s.size,
            filename: s.rfilename,
        })
        .collect();

    HfModel {
        id: raw.model_id,
        name,
        downloads: raw.downloads,
        likes: raw.likes,
        gguf_files,
    }
}

// ---------------------------------------------------------------------------
// Public search function
// ---------------------------------------------------------------------------

/// Search HuggingFace for GGUF models matching `params`.
///
/// Results are cached per unique `(query, limit)` pair for [`CACHE_TTL`].
/// Subsequent calls within the TTL are served from memory without a network
/// round-trip.
///
/// # Errors
///
/// Returns a `String` error on network failure or JSON parse error.
pub async fn search_hf(params: HfSearchParams) -> Result<Vec<HfModel>, String> {
    let key = cache_key(&params);

    // Fast path: check read lock first.
    {
        let guard = cache().read().await;
        if let Some(entry) = guard.iter().find(|e| e.params == key) {
            if entry.fetched_at.elapsed() < CACHE_TTL {
                return Ok(entry.results.clone());
            }
        }
    }

    // Slow path: fetch from HF API.
    let limit = params.limit.clamp(1, 50);
    // Allow tests (and future env overrides) to redirect requests to a mock server.
    let base = std::env::var("HF_API_BASE_URL")
        .unwrap_or_else(|_| "https://huggingface.co".to_owned());
    let url = format!(
        "{}/api/models?search={}&filter=gguf&limit={}&sort=downloads&full=true",
        base.trim_end_matches('/'),
        urlencoding_simple(&params.query),
        limit
    );

    let client = reqwest::Client::builder()
        .user_agent("nclaw-desktop/1.1.1")
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| format!("http client: {e}"))?;

    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("HF API request failed: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("HF API returned HTTP {}", resp.status()));
    }

    let raw: Vec<HfApiModel> = resp
        .json()
        .await
        .map_err(|e| format!("HF API JSON parse: {e}"))?;

    let results: Vec<HfModel> = raw.into_iter().map(map_model).collect();

    // Write into cache (evict stale entry for the same key if present).
    {
        let mut guard = cache().write().await;
        guard.retain(|e| e.params != key);
        guard.push(CacheEntry {
            params: key,
            results: results.clone(),
            fetched_at: Instant::now(),
        });
    }

    Ok(results)
}

/// Minimal URL percent-encoding for the query string parameter.
///
/// Encodes spaces as `%20` and passes through alphanumeric + `-_.~`.
/// Sufficient for a search query — not a full RFC 3986 encoder.
fn urlencoding_simple(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            b' ' => out.push_str("%20"),
            other => out.push_str(&format!("%{:02X}", other)),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_quant_standard() {
        assert_eq!(extract_quant("model-Q4_K_M.gguf"), Some("Q4_K_M".into()));
        assert_eq!(extract_quant("model-Q8_0.gguf"), Some("Q8_0".into()));
        assert_eq!(extract_quant("model-IQ2_XS.gguf"), Some("IQ2_XS".into()));
    }

    #[test]
    fn extract_quant_no_quant() {
        assert_eq!(extract_quant("model.gguf"), None);
        assert_eq!(extract_quant("llama-3.gguf"), None);
    }

    #[test]
    fn extract_quant_f16() {
        assert_eq!(extract_quant("model-F16.gguf"), Some("F16".into()));
    }

    #[test]
    fn urlencoding_spaces() {
        assert_eq!(urlencoding_simple("llama 3"), "llama%203");
    }

    #[test]
    fn urlencoding_safe_chars() {
        assert_eq!(urlencoding_simple("mistral-7b"), "mistral-7b");
    }

    #[test]
    fn map_model_name_extraction() {
        let raw = HfApiModel {
            model_id: "bartowski/Meta-Llama-3-8B-Instruct-GGUF".into(),
            downloads: 100,
            likes: 50,
            siblings: vec![HfSibling {
                rfilename: "Meta-Llama-3-8B-Instruct-Q4_K_M.gguf".into(),
                size: Some(4_800_000_000),
            }],
        };
        let model = map_model(raw);
        assert_eq!(model.name, "Meta-Llama-3-8B-Instruct-GGUF");
        assert_eq!(model.gguf_files.len(), 1);
        assert_eq!(model.gguf_files[0].quant, Some("Q4_K_M".into()));
        assert_eq!(model.gguf_files[0].size_bytes, Some(4_800_000_000));
    }

    #[test]
    fn cache_key_normalises_case() {
        let key1 = cache_key(&HfSearchParams { query: "Llama".into(), limit: 10 });
        let key2 = cache_key(&HfSearchParams { query: "llama".into(), limit: 10 });
        assert_eq!(key1, key2);
    }
}
