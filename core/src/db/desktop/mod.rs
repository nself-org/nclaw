//! Desktop database engines for nClaw.
//!
//! Decision #4: pglite (Postgres-on-WASM) is the default. When pglite cannot host
//! pgvector or ltree (e.g. the WASM bundle predates those extensions), compile with
//! `--features embedded-pg` to activate the embedded-postgres fallback instead.

pub mod embedded_pg_engine;
pub mod pglite_engine;

use std::path::PathBuf;

use crate::error::CoreError;

/// Abstraction over a local Postgres-compatible database engine for the desktop target.
pub trait DbEngine: Send + Sync {
    /// Start the engine, initialising data at `data_dir`. Returns a connection URL on success.
    fn start(&mut self, data_dir: &std::path::Path) -> Result<String, CoreError>;
    /// Gracefully stop the engine.
    fn stop(&mut self) -> Result<(), CoreError>;
    /// Short human-readable identifier used for diagnostics and smoke tests.
    fn engine_name(&self) -> &'static str;
}

/// Desktop database wrapper. Holds the selected engine and delegates all operations to it.
pub struct DesktopDb {
    engine: Box<dyn DbEngine>,
}

impl DesktopDb {
    /// Construct with the compile-time default engine.
    ///
    /// With `--features embedded-pg` the fallback embedded-postgres engine is used;
    /// otherwise pglite is selected (pending S16.T01b WASM bundle integration).
    pub fn new_default(data_dir: PathBuf) -> Self {
        #[cfg(feature = "embedded-pg")]
        return Self::new_embedded_pg(data_dir);

        #[cfg(not(feature = "embedded-pg"))]
        return Self::new_pglite(data_dir);
    }

    /// Construct using the pglite engine explicitly.
    pub fn new_pglite(_data_dir: PathBuf) -> Self {
        Self {
            engine: Box::new(pglite_engine::PgliteEngine::new()),
        }
    }

    /// Construct using the embedded-postgres engine explicitly.
    /// Only available when compiled with `--features embedded-pg`.
    #[cfg(feature = "embedded-pg")]
    pub fn new_embedded_pg(data_dir: PathBuf) -> Self {
        Self {
            engine: Box::new(embedded_pg_engine::EmbeddedPgEngine::new(data_dir)),
        }
    }

    /// Start the underlying engine. Returns a connection URL.
    pub fn start(&mut self, data_dir: &std::path::Path) -> Result<String, CoreError> {
        self.engine.start(data_dir)
    }

    /// Stop the underlying engine.
    pub fn stop(&mut self) -> Result<(), CoreError> {
        self.engine.stop()
    }

    /// Name of the active engine, e.g. `"pglite"` or `"embedded-pg"`.
    pub fn engine_name(&self) -> &'static str {
        self.engine.engine_name()
    }
}
