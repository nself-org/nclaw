//! Resume helpers — partial-file paths and byte-offset detection.

use std::path::{Path, PathBuf};

/// Path to the in-progress partial file for a model ID.
pub fn partial_path(cache_dir: &Path, id: &str) -> PathBuf {
    cache_dir.join(format!("{id}.gguf.partial"))
}

/// Final destination path for a completed model.
pub fn final_path(cache_dir: &Path, id: &str) -> PathBuf {
    cache_dir.join(format!("{id}.gguf"))
}

/// Byte count already on disk for a partial download.
/// Returns 0 if no partial file exists or the file cannot be read.
pub fn existing_partial_size(cache_dir: &Path, id: &str) -> u64 {
    partial_path(cache_dir, id)
        .metadata()
        .map(|m| m.len())
        .unwrap_or(0)
}
