//! T-2083: File sync — server pushes files to local filesystem.
//! Writes are restricted to allowed directories from config.

use std::path::{Path, PathBuf};

/// Handle a file_write command from the server.
/// Validates path against allowed directories before writing.
pub async fn handle_file_write(path: &str, content: &str, _app_handle: &tauri::AppHandle) {
    let config = crate::config::load_config();
    let expanded = expand_tilde(path);

    if !is_path_allowed(&expanded, &config.allowed_paths) {
        tracing::warn!(path = %path, "file_write rejected — path not in allowed list");
        // Could show a Tauri dialog for approval here (T-2087)
        return;
    }

    // Create parent directories
    if let Some(parent) = Path::new(&expanded).parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            tracing::warn!(path = %expanded, error = %e, "failed to create parent dirs");
            return;
        }
    }

    match std::fs::write(&expanded, content) {
        Ok(_) => tracing::info!(path = %expanded, bytes = content.len(), "file written"),
        Err(e) => tracing::warn!(path = %expanded, error = %e, "file_write failed"),
    }
}

fn expand_tilde(path: &str) -> String {
    if path.starts_with("~/") {
        if let Some(home) = dirs::home_dir() {
            return path.replacen("~", &home.to_string_lossy(), 1);
        }
    }
    path.to_string()
}

fn is_path_allowed(path: &str, allowed: &[String]) -> bool {
    let path_buf = PathBuf::from(path);
    for pattern in allowed {
        let expanded = expand_tilde(pattern);
        // Simple glob: check if path starts with pattern prefix (before *)
        let prefix = expanded.split('*').next().unwrap_or(&expanded);
        if path_buf.starts_with(prefix) {
            return true;
        }
    }
    false
}
