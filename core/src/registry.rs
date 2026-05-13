//! Model registry — compile-time const catalog of default and alternative LLM models per tier.
//!
//! Decision #9 defines five model tiers (T0–T4) with one default model per tier.
//! This module maintains the catalog in const form (no I/O, no async, fully compile-time).
//!
//! SHA256 hashes are populated at build time by the model-download CLI tool (T07).
//! Pending hashes are marked with "TBD-PEND-DOWNLOAD" and computed when the model is downloaded.

use crate::tier::Tier;
use serde::{Deserialize, Serialize};

/// Metadata for a single LLM model.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelEntry {
    /// Unique model identifier: {org}/{model}-{quantization}
    pub id: &'static str,
    /// Human-readable display name with quantization
    pub display_name: &'static str,
    /// Hardware tier this model targets (T0–T4)
    pub tier: Tier,
    /// Hugging Face repository: e.g., "Qwen/Qwen2.5-0.5B-Instruct-GGUF"
    pub hf_repo: &'static str,
    /// Model file in repo: e.g., "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    pub hf_file: &'static str,
    /// SHA256 hash (hex string). Use "TBD-PEND-DOWNLOAD" until model is downloaded.
    pub sha256: &'static str,
    /// Model file size in MB
    pub size_mb: u32,
    /// Context window (tokens)
    pub context_window: u32,
    /// License identifier: maps to canonical license metadata below
    pub license_id: &'static str,
    /// License URL for user reference
    pub license_url: &'static str,
    /// License summary line for UI display
    pub license_summary: &'static str,
}

/// Default model catalog — one entry per tier (T0–T4).
/// These are the recommended models for each tier, shipping by default.
pub static DEFAULT_CATALOG: &'static [ModelEntry] = &[
    // T0: Qwen 2.5 0.5B (352 MB, mobile/IoT minimal)
    ModelEntry {
        id: "qwen2.5-0.5b-q4km",
        display_name: "Qwen 2.5 0.5B Instruct (Q4_K_M)",
        tier: Tier::T0,
        hf_repo: "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
        hf_file: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
        sha256: "TBD-PEND-DOWNLOAD", // computed by model-download T07 CLI
        size_mb: 352,
        context_window: 32768,
        license_id: "qwen-research-license",
        license_url: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/blob/main/LICENSE",
        license_summary: "Apache-2 derivative; commercial OK",
    },
    // T1: Llama 3.2 1B (770 MB, entry-level devices)
    ModelEntry {
        id: "llama3.2-1b-q4km",
        display_name: "Llama 3.2 1B Instruct (Q4_K_M)",
        tier: Tier::T1,
        hf_repo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
        hf_file: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 770,
        context_window: 128000,
        license_id: "llama-community-license",
        license_url: "https://www.llama.com/llama3_2/license/",
        license_summary: "Community license; free use up to 700M MAU; broad commercial allowance",
    },
    // T2: Llama 3.2 3B (2020 MB, mainstream/mid-range)
    ModelEntry {
        id: "llama3.2-3b-q4km",
        display_name: "Llama 3.2 3B Instruct (Q4_K_M)",
        tier: Tier::T2,
        hf_repo: "bartowski/Llama-3.2-3B-Instruct-GGUF",
        hf_file: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 2020,
        context_window: 128000,
        license_id: "llama-community-license",
        license_url: "https://www.llama.com/llama3_2/license/",
        license_summary: "Community license; free use up to 700M MAU; broad commercial allowance",
    },
    // T3: Llama 3.1 8B (4920 MB, workstation/capable GPU)
    ModelEntry {
        id: "llama3.1-8b-q4km",
        display_name: "Llama 3.1 8B Instruct (Q4_K_M)",
        tier: Tier::T3,
        hf_repo: "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
        hf_file: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 4920,
        context_window: 128000,
        license_id: "llama-community-license",
        license_url: "https://www.llama.com/llama3_2/license/",
        license_summary: "Community license; free use up to 700M MAU; broad commercial allowance",
    },
    // T4: Qwen 2.5 14B (8990 MB, flagship/high-end workstation, opt-in only)
    ModelEntry {
        id: "qwen2.5-14b-q4km",
        display_name: "Qwen 2.5 14B Instruct (Q4_K_M)",
        tier: Tier::T4,
        hf_repo: "bartowski/Qwen2.5-14B-Instruct-GGUF",
        hf_file: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 8990,
        context_window: 131072,
        license_id: "qwen-research-license",
        license_url: "https://huggingface.co/Qwen/Qwen2.5-14B-Instruct/blob/main/LICENSE",
        license_summary: "Apache-2 derivative; commercial OK",
    },
];

/// Alternative model catalog — fallbacks and specialized models per tier.
/// Users can switch to alternatives if default doesn't meet their needs.
pub static ALTERNATIVE_CATALOG: &'static [ModelEntry] = &[
    // T1 alt: Phi 3.5 Mini (2.3B, 1100 MB)
    ModelEntry {
        id: "phi3.5-mini-q4km",
        display_name: "Phi 3.5 Mini (Q4_K_M)",
        tier: Tier::T1,
        hf_repo: "bartowski/Phi-3.5-mini-instruct-GGUF",
        hf_file: "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 1100,
        context_window: 128000,
        license_id: "mit",
        license_url: "https://opensource.org/license/mit",
        license_summary: "MIT — fully permissive",
    },
    // T2 alt: Gemma 2 2B (1200 MB)
    ModelEntry {
        id: "gemma2-2b-q4km",
        display_name: "Gemma 2 2B Instruct (Q4_K_M)",
        tier: Tier::T2,
        hf_repo: "bartowski/gemma-2-2b-it-GGUF",
        hf_file: "gemma-2-2b-it-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 1200,
        context_window: 8192,
        license_id: "gemma-tos",
        license_url: "https://ai.google.dev/gemma/terms",
        license_summary: "Google Terms of Use; commercial allowed with attribution",
    },
    // T3 alt: Mistral 7B Instruct v0.3 (4000 MB)
    ModelEntry {
        id: "mistral-7b-v0.3-q4km",
        display_name: "Mistral 7B Instruct v0.3 (Q4_K_M)",
        tier: Tier::T3,
        hf_repo: "bartowski/Mistral-7B-Instruct-v0.3-GGUF",
        hf_file: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 4000,
        context_window: 32768,
        license_id: "mistral-research-license",
        license_url: "https://mistral.ai/terms/",
        license_summary: "Non-commercial only — flagged for review",
    },
    // T4 alt: Llama 3.1 70B (40000 MB, requires flagship GPU, explicit opt-in)
    ModelEntry {
        id: "llama3.1-70b-q4km",
        display_name: "Llama 3.1 70B Instruct (Q4_K_M)",
        tier: Tier::T4,
        hf_repo: "bartowski/Meta-Llama-3.1-70B-Instruct-GGUF",
        hf_file: "Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 40000,
        context_window: 128000,
        license_id: "llama-community-license",
        license_url: "https://www.llama.com/llama3_2/license/",
        license_summary: "Community license; free use up to 700M MAU; broad commercial allowance",
    },
    // Embeddings-only alt: BGE Small (T2+, 130 MB, for semantic search)
    ModelEntry {
        id: "bge-small-en-q4km",
        display_name: "BGE Small EN v1.5 (Q4_K_M)",
        tier: Tier::T2,
        hf_repo: "bartowski/bge-small-en-v1.5-GGUF",
        hf_file: "bge-small-en-v1.5-Q4_K_M.gguf",
        sha256: "TBD-PEND-DOWNLOAD",
        size_mb: 130,
        context_window: 512,
        license_id: "apache-2.0",
        license_url: "https://www.apache.org/licenses/LICENSE-2.0",
        license_summary: "Apache 2.0 — fully permissive with patent grant",
    },
];

/// Get the default model entry for a given tier.
/// Returns None only for invalid tier assignments (should not happen in practice).
pub fn default_for_tier(tier: Tier) -> Option<&'static ModelEntry> {
    DEFAULT_CATALOG.iter().find(|m| m.tier == tier)
}

/// Find a model entry by its ID in both catalogs.
/// Returns None if the ID does not exist.
pub fn find_by_id(id: &str) -> Option<&'static ModelEntry> {
    DEFAULT_CATALOG
        .iter()
        .chain(ALTERNATIVE_CATALOG.iter())
        .find(|m| m.id == id)
}

/// List all alternative models available for a given tier.
pub fn list_alternatives_for_tier(tier: Tier) -> impl Iterator<Item = &'static ModelEntry> {
    ALTERNATIVE_CATALOG.iter().filter(move |m| m.tier == tier)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_each_tier_has_default() {
        assert!(
            default_for_tier(Tier::T0).is_some(),
            "T0 must have a default"
        );
        assert!(
            default_for_tier(Tier::T1).is_some(),
            "T1 must have a default"
        );
        assert!(
            default_for_tier(Tier::T2).is_some(),
            "T2 must have a default"
        );
        assert!(
            default_for_tier(Tier::T3).is_some(),
            "T3 must have a default"
        );
        assert!(
            default_for_tier(Tier::T4).is_some(),
            "T4 must have a default"
        );
    }

    #[test]
    fn test_no_duplicate_ids() {
        let mut ids = Vec::new();
        for entry in DEFAULT_CATALOG.iter().chain(ALTERNATIVE_CATALOG.iter()) {
            assert!(
                !ids.contains(&entry.id),
                "duplicate model ID found: {}",
                entry.id
            );
            ids.push(entry.id);
        }
    }

    #[test]
    fn test_all_license_urls_valid() {
        for entry in DEFAULT_CATALOG.iter().chain(ALTERNATIVE_CATALOG.iter()) {
            assert!(
                entry.license_url.starts_with("https://"),
                "license URL must start with https://: {}",
                entry.license_url
            );
        }
    }

    #[test]
    fn test_all_sizes_positive() {
        for entry in DEFAULT_CATALOG.iter().chain(ALTERNATIVE_CATALOG.iter()) {
            assert!(entry.size_mb > 0, "size_mb must be > 0 for {}", entry.id);
        }
    }

    #[test]
    fn test_find_by_id() {
        let entry = find_by_id("qwen2.5-0.5b-q4km");
        assert!(entry.is_some(), "should find default T0 model");
        assert_eq!(entry.unwrap().tier, Tier::T0);

        let alt = find_by_id("phi3.5-mini-q4km");
        assert!(alt.is_some(), "should find alternative T1 model");
        assert_eq!(alt.unwrap().tier, Tier::T1);

        let missing = find_by_id("nonexistent-model");
        assert!(missing.is_none(), "nonexistent model should not be found");
    }

    #[test]
    fn test_alternatives_for_tier() {
        let t1_alts: Vec<_> = list_alternatives_for_tier(Tier::T1).collect();
        assert_eq!(t1_alts.len(), 1, "T1 should have 1 alternative");
        assert_eq!(t1_alts[0].id, "phi3.5-mini-q4km");

        let t3_alts: Vec<_> = list_alternatives_for_tier(Tier::T3).collect();
        assert_eq!(t3_alts.len(), 1, "T3 should have 1 alternative");
        assert_eq!(t3_alts[0].id, "mistral-7b-v0.3-q4km");

        let t0_alts: Vec<_> = list_alternatives_for_tier(Tier::T0).collect();
        assert!(t0_alts.is_empty(), "T0 should have no alternatives");
    }
}
