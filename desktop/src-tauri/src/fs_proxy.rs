//! T-2087: Sandboxed filesystem proxy.
//! Server requests file read/write, companion checks against allowlist.
//! New paths require GUI approval via Tauri dialog.

use std::collections::HashSet;
use std::sync::Mutex;

/// Tracks approved paths for this session.
pub struct FsProxy {
    approved_paths: Mutex<HashSet<String>>,
    config_allowed: Vec<String>,
}

impl FsProxy {
    pub fn new(config_allowed: Vec<String>) -> Self {
        Self {
            approved_paths: Mutex::new(HashSet::new()),
            config_allowed,
        }
    }

    /// Check if a path is allowed (config or session-approved).
    pub fn is_allowed(&self, path: &str) -> bool {
        // Check config allowlist first
        for pattern in &self.config_allowed {
            let prefix = pattern.split('*').next().unwrap_or(pattern);
            if path.starts_with(prefix) {
                return true;
            }
        }
        // Check session-approved paths
        let approved = self.approved_paths.lock().unwrap_or_else(|p| p.into_inner());
        approved.contains(path)
    }

    /// Approve a path for this session.
    pub fn approve(&self, path: &str) {
        let mut approved = self.approved_paths.lock().unwrap_or_else(|p| p.into_inner());
        approved.insert(path.to_string());
    }
}
