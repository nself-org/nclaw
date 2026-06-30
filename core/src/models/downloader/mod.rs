//! Background GGUF model downloader with resume, HF → CDN fallback, and SHA256 verification.
//!
//! # Concurrency
//! `Downloader` is `Clone + Send + Sync`. Concurrency limits are the caller's responsibility —
//! run multiple `download()` calls behind a `tokio::sync::Semaphore` if needed.
//!
//! # Download flow
//! 1. Pre-check available disk space (requires 1.2× `size_mb`).
//! 2. Attempt Hugging Face CDN with `Range` header if a `.partial` file exists.
//! 3. On any HF network failure, fall back to `cdn.nself.org`.
//! 4. After transfer completes, verify SHA256.
//!    - If the registry hash is `"TBD-PEND-DOWNLOAD"`, verification is skipped.
//!    - On mismatch, retry from the alternate source once; permanent failure yields `Failed`.
//! 5. Rename `.partial` → `{id}.gguf`.

pub mod resume;

use async_stream::stream;
use futures::TryStreamExt;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use tokio::io::AsyncWriteExt;

use crate::registry::ModelEntry;

// Re-export for callers who only import the downloader module.
pub use resume::{existing_partial_size, final_path, partial_path};

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Progress events emitted by [`Downloader::download`].
#[derive(Debug, Clone)]
pub enum DownloadEvent {
    /// Bytes received so far and total expected bytes.
    Progress { downloaded: u64, total: u64 },
    /// SHA256 verification is underway.
    Verifying,
    /// Verification passed (or was skipped for TBD hashes).
    Verified,
    /// A terminal failure occurred.
    Failed { kind: DownloadError },
}

/// Error variants for download failures.
#[derive(Debug, Clone, thiserror::Error)]
pub enum DownloadError {
    #[error("network: {0}")]
    Network(String),
    #[error("insufficient disk space")]
    InsufficientDisk,
    #[error("sha256 mismatch")]
    Sha256Mismatch,
    #[error("io: {0}")]
    Io(String),
}

// ---------------------------------------------------------------------------
// Downloader
// ---------------------------------------------------------------------------

/// Stateless HTTP downloader.  Clone it freely — the inner `reqwest::Client` is `Arc`-backed.
#[derive(Debug, Clone)]
pub struct Downloader {
    client: reqwest::Client,
    cache_dir: PathBuf,
}

impl Downloader {
    /// Create a downloader that stores model files in `cache_dir`.
    pub fn new(cache_dir: impl Into<PathBuf>) -> Self {
        Self {
            client: reqwest::Client::builder()
                .user_agent("libnclaw-downloader/0.1")
                .build()
                .expect("reqwest client build failed"),
            cache_dir: cache_dir.into(),
        }
    }

    /// Return the cache directory in use.
    pub fn cache_dir(&self) -> &std::path::Path {
        &self.cache_dir
    }

    /// Stream download events for a model entry.
    ///
    /// The stream is lazy — polling drives the download.  Drop it to cancel (partial file
    /// is preserved so the next call can resume).
    pub fn download(
        &self,
        entry: &ModelEntry,
    ) -> impl tokio_stream::Stream<Item = DownloadEvent> + Send + 'static {
        let client = self.client.clone();
        let cache_dir = self.cache_dir.clone();
        let id = entry.id;
        let hf_url = format!(
            "https://huggingface.co/{}/resolve/main/{}",
            entry.hf_repo, entry.hf_file
        );
        let cdn_url = format!("https://cdn.nself.org/models/{}/{}.gguf", id, entry.sha256);
        let size_mb = entry.size_mb;
        let sha256_expected = entry.sha256;

        stream! {
            // ------------------------------------------------------------------
            // 1. Disk pre-check
            // ------------------------------------------------------------------
            let required_bytes = (size_mb as u64) * 1024 * 1024 * 12 / 10; // ×1.2
            match fs2::available_space(&cache_dir) {
                Ok(free) if free < required_bytes => {
                    yield DownloadEvent::Failed { kind: DownloadError::InsufficientDisk };
                    return;
                }
                Err(e) => {
                    // If we cannot read free space, log and continue — better to try than refuse.
                    tracing::warn!("disk space check failed for {}: {}", cache_dir.display(), e);
                }
                Ok(_) => {}
            }

            // ------------------------------------------------------------------
            // 2. Attempt download from primary (HF) then fallback (CDN)
            // ------------------------------------------------------------------
            let outcome = download_with_fallback(
                &client,
                &cache_dir,
                id,
                &hf_url,
                &cdn_url,
                sha256_expected,
            )
            .await;

            match outcome {
                Err(kind) => {
                    yield DownloadEvent::Failed { kind };
                    return;
                }
                Ok(events) => {
                    for ev in events {
                        yield ev;
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Internal download logic
// ---------------------------------------------------------------------------

/// Drive the full download with HF → CDN fallback.
/// Returns a vec of events to yield (Progress* + Verifying + Verified) or an error.
async fn download_with_fallback(
    client: &reqwest::Client,
    cache_dir: &std::path::Path,
    id: &'static str,
    hf_url: &str,
    cdn_url: &str,
    sha256_expected: &'static str,
) -> Result<Vec<DownloadEvent>, DownloadError> {
    // Try primary source.
    let primary = fetch_to_partial(client, cache_dir, id, hf_url).await;

    let events = match primary {
        Ok(evs) => evs,
        Err(_hf_err) => {
            // HF failed — remove any corrupt partial and retry from CDN.
            let _ = tokio::fs::remove_file(partial_path(cache_dir, id)).await;
            fetch_to_partial(client, cache_dir, id, cdn_url).await?
        }
    };

    // ------------------------------------------------------------------
    // SHA256 verification
    // ------------------------------------------------------------------
    let mut all_events = events;
    all_events.push(DownloadEvent::Verifying);

    let partial = partial_path(cache_dir, id);

    if sha256_expected == "TBD-PEND-DOWNLOAD" {
        // Hash not yet pinned — skip verification.
        tracing::debug!("skipping SHA256 for {} (TBD-PEND-DOWNLOAD)", id);
    } else {
        let computed = compute_sha256(&partial).await?;
        if computed != sha256_expected.to_lowercase() {
            // One retry from the alternate source.
            let _ = tokio::fs::remove_file(&partial).await;
            let retry = fetch_to_partial(client, cache_dir, id, cdn_url).await;
            match retry {
                Err(e) => return Err(e),
                Ok(retry_evs) => {
                    all_events.extend(retry_evs);
                    let computed2 = compute_sha256(&partial).await?;
                    if computed2 != sha256_expected.to_lowercase() {
                        let _ = tokio::fs::remove_file(&partial).await;
                        return Err(DownloadError::Sha256Mismatch);
                    }
                }
            }
        }
    }

    // Rename partial → final.
    let dest = final_path(cache_dir, id);
    tokio::fs::rename(&partial, &dest)
        .await
        .map_err(|e| DownloadError::Io(e.to_string()))?;

    all_events.push(DownloadEvent::Verified);
    Ok(all_events)
}

/// Stream response bytes into a `.partial` file, appending if an existing partial is found.
/// Returns Progress events collected during the transfer.
async fn fetch_to_partial(
    client: &reqwest::Client,
    cache_dir: &std::path::Path,
    id: &str,
    url: &str,
) -> Result<Vec<DownloadEvent>, DownloadError> {
    let partial = partial_path(cache_dir, id);
    let resume_offset = existing_partial_size(cache_dir, id);

    let mut req = client.get(url);
    if resume_offset > 0 {
        req = req.header("Range", format!("bytes={}-", resume_offset));
    }

    let resp = req
        .send()
        .await
        .map_err(|e| DownloadError::Network(e.to_string()))?;

    if !resp.status().is_success() && resp.status().as_u16() != 206 {
        return Err(DownloadError::Network(format!(
            "HTTP {}",
            resp.status().as_u16()
        )));
    }

    // Content-Length tells us how many bytes remain; total = offset + remaining.
    let content_length = resp.content_length().unwrap_or(0);
    let total = resume_offset + content_length;

    // Ensure cache_dir exists.
    tokio::fs::create_dir_all(cache_dir)
        .await
        .map_err(|e| DownloadError::Io(e.to_string()))?;

    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&partial)
        .await
        .map_err(|e| DownloadError::Io(e.to_string()))?;

    let mut downloaded = resume_offset;
    let mut events: Vec<DownloadEvent> = vec![DownloadEvent::Progress { downloaded, total }];

    let mut stream = resp.bytes_stream();
    // Flush progress events every ~256 KB to keep the stream responsive without flooding.
    let mut since_last_event: u64 = 0;
    const PROGRESS_INTERVAL: u64 = 256 * 1024;

    while let Some(chunk) = stream
        .try_next()
        .await
        .map_err(|e| DownloadError::Network(e.to_string()))?
    {
        file.write_all(&chunk)
            .await
            .map_err(|e| DownloadError::Io(e.to_string()))?;
        let len = chunk.len() as u64;
        downloaded += len;
        since_last_event += len;

        if since_last_event >= PROGRESS_INTERVAL || downloaded == total {
            events.push(DownloadEvent::Progress { downloaded, total });
            since_last_event = 0;
        }
    }

    file.flush()
        .await
        .map_err(|e| DownloadError::Io(e.to_string()))?;

    Ok(events)
}

/// Compute the lowercase hex SHA256 of a file on disk.
async fn compute_sha256(path: &std::path::Path) -> Result<String, DownloadError> {
    let data = tokio::fs::read(path)
        .await
        .map_err(|e| DownloadError::Io(e.to_string()))?;
    let mut hasher = Sha256::new();
    hasher.update(&data);
    Ok(format!("{:x}", hasher.finalize()))
}
