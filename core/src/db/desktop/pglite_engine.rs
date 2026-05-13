//! pglite engine: Postgres-on-WASM via wasmtime.
//!
//! NOTE: WASM bundle integration is a follow-up sub-ticket (S16.T01b). This module
//! provides the engine surface so downstream code compiles. Calling `start()` before
//! the WASM bundle is integrated returns `CoreError::Other` with a clear message.
//! No panics, no unimplemented!() macros.

use std::path::Path;

use crate::db::desktop::DbEngine;
use crate::error::CoreError;

/// pglite engine handle. Will hold the wasmtime `Store` and `Instance` once S16.T01b lands.
pub struct PgliteEngine {
    started: bool,
}

impl PgliteEngine {
    /// Construct a new (not-yet-started) pglite engine.
    pub fn new() -> Self {
        Self { started: false }
    }
}

impl Default for PgliteEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl DbEngine for PgliteEngine {
    fn start(&mut self, _data_dir: &Path) -> Result<String, CoreError> {
        // wasmtime + pglite.wasm bundling lands in S16.T01b.
        // Returning a clear error so callers can detect the pending state and either
        // fall back to embedded-pg or surface a user-friendly message.
        Err(CoreError::Other(
            "pglite WASM integration pending (S16.T01b)".into(),
        ))
    }

    fn stop(&mut self) -> Result<(), CoreError> {
        self.started = false;
        Ok(())
    }

    fn engine_name(&self) -> &'static str {
        "pglite"
    }
}
