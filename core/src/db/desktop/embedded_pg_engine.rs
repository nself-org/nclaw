//! Embedded-postgres fallback engine.
//!
//! Launches a real `postgres` binary subprocess scoped to the user's app-data directory.
//! Used when the pglite WASM bundle cannot host `pgvector` or `ltree`.
//!
//! Enable with: `--features embedded-pg`
//!
//! NOTE: `postgresql_embedded` integration (the subprocess lifecycle) is a follow-up
//! sub-ticket (S16.T01b). This module provides the engine surface so downstream code
//! compiles. Calling `start()` returns `CoreError::Other` with a clear message until
//! the integration lands.

use std::path::{Path, PathBuf};

use crate::db::desktop::DbEngine;
use crate::error::CoreError;

/// Embedded-postgres engine handle.
///
/// Will hold a `postgresql_embedded::PostgreSQL` instance once S16.T01b lands.
pub struct EmbeddedPgEngine {
    data_dir: PathBuf,
    /// Placeholder for the postgresql_embedded process handle (S16.T01b).
    _handle: Option<()>,
}

impl EmbeddedPgEngine {
    /// Construct a new engine that will store data in `data_dir`.
    pub fn new(data_dir: PathBuf) -> Self {
        Self {
            data_dir,
            _handle: None,
        }
    }
}

impl DbEngine for EmbeddedPgEngine {
    fn start(&mut self, data_dir: &Path) -> Result<String, CoreError> {
        let _ = data_dir; // will be consumed by postgresql_embedded in S16.T01b
        let _ = &self.data_dir;
        // postgresql_embedded::PostgreSQL::default() and lifecycle management lands in S16.T01b.
        Err(CoreError::Other(
            "embedded-postgres integration pending (S16.T01b)".into(),
        ))
    }

    fn stop(&mut self) -> Result<(), CoreError> {
        self._handle = None;
        Ok(())
    }

    fn engine_name(&self) -> &'static str {
        "embedded-pg"
    }
}
