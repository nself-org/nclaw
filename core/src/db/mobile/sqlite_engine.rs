//! SQLite + sqlite-vec engine for mobile platforms (iOS, Android).

#[cfg(feature = "mobile-sqlite")]
use rusqlite::Connection;

use crate::error::CoreError;
use std::path::Path;

/// SQLite engine wrapper for mobile targets.
///
/// When the `mobile-sqlite` feature is enabled, this wraps a rusqlite Connection.
/// When disabled, it compiles to a zero-sized phantom marker.
pub struct MobileSqliteEngine {
    #[cfg(feature = "mobile-sqlite")]
    conn: Option<Connection>,
    #[cfg(not(feature = "mobile-sqlite"))]
    _phantom: std::marker::PhantomData<()>,
}

impl MobileSqliteEngine {
    /// Create a new engine instance.
    pub fn new() -> Self {
        Self {
            #[cfg(feature = "mobile-sqlite")]
            conn: None,
            #[cfg(not(feature = "mobile-sqlite"))]
            _phantom: std::marker::PhantomData,
        }
    }

    /// Open a database at the given path.
    #[cfg(feature = "mobile-sqlite")]
    pub fn open(&mut self, path: &Path) -> Result<(), CoreError> {
        let conn = Connection::open(path)
            .map_err(|e| CoreError::Other(format!("SQLite open failed: {}", e)))?;

        // Try to load sqlite-vec extension (best-effort; real bundling in S16.T02b).
        // Once S16.T02b ships with static-library bundling, uncomment:
        // unsafe { conn.load_extension("vec0", None).ok(); }

        self.conn = Some(conn);
        Ok(())
    }

    /// Open a database at the given path (disabled build).
    #[cfg(not(feature = "mobile-sqlite"))]
    pub fn open(&mut self, _path: &Path) -> Result<(), CoreError> {
        Err(CoreError::Other(
            "mobile-sqlite feature not enabled at compile time".into(),
        ))
    }

    /// Get the engine name.
    pub fn engine_name(&self) -> &'static str {
        "sqlite+vec"
    }
}

impl Default for MobileSqliteEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// Mobile database wrapper exposing the SQLite engine.
pub struct MobileDb {
    engine: MobileSqliteEngine,
}

impl MobileDb {
    /// Create a new mobile database instance.
    pub fn new() -> Self {
        Self {
            engine: MobileSqliteEngine::new(),
        }
    }

    /// Open the database at the given path.
    pub fn open(&mut self, path: &Path) -> Result<(), CoreError> {
        self.engine.open(path)
    }

    /// Get the engine name (for diagnostics/logging).
    pub fn engine_name(&self) -> &'static str {
        self.engine.engine_name()
    }
}

impl Default for MobileDb {
    fn default() -> Self {
        Self::new()
    }
}
