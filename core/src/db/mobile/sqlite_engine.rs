//! SQLite + SQLCipher engine for mobile platforms (iOS, Android).
//!
//! # Encryption
//! All databases are opened with SQLCipher via `PRAGMA key`. A 32-byte key
//! derived by [`crate::db::encryption::derive_key`] (Argon2id) is supplied by
//! the caller on every open. The PRAGMA must be the very first statement on a
//! new connection — any query before it would return SQLITE_NOTADB.
//!
//! # Key validation
//! After applying the PRAGMA a lightweight sanity query (`SELECT count(*) FROM
//! sqlite_master`) is run. If the key is wrong (or the file is plaintext) SQLite
//! returns an error and we translate it to [`crate::error::DbError::DbDecryptionFailed`]
//! rather than surfacing a raw rusqlite message.
//!
//! # Migration
//! No existing production mobile databases exist (nClaw mobile is pre-release).
//! This is a clean cutover — no plaintext-to-encrypted migration is required.

#[cfg(feature = "mobile-sqlite")]
use rusqlite::Connection;

use crate::error::CoreError;
#[cfg(feature = "mobile-sqlite")]
use crate::error::DbError;
use std::path::Path;

/// SQLite + SQLCipher engine wrapper for mobile targets.
///
/// When the `mobile-sqlite` feature is enabled, this wraps a rusqlite Connection
/// backed by the bundled-sqlcipher build. When disabled, it compiles to a zero-sized
/// phantom marker so the type still exists in non-mobile builds.
pub struct MobileSqliteEngine {
    #[cfg(feature = "mobile-sqlite")]
    conn: Option<Connection>,
    #[cfg(not(feature = "mobile-sqlite"))]
    _phantom: std::marker::PhantomData<()>,
}

impl MobileSqliteEngine {
    /// Create a new, unopened engine instance.
    pub fn new() -> Self {
        Self {
            #[cfg(feature = "mobile-sqlite")]
            conn: None,
            #[cfg(not(feature = "mobile-sqlite"))]
            _phantom: std::marker::PhantomData,
        }
    }

    /// Open an encrypted database at `path` using the supplied 32-byte SQLCipher key.
    ///
    /// The sequence is:
    /// 1. Open the connection with rusqlite (bundled-sqlcipher build).
    /// 2. Execute `PRAGMA key = "x'...'"` — **must** be first statement.
    /// 3. Execute a sanity `SELECT count(*) FROM sqlite_master` to verify the key.
    ///    A wrong key or plaintext file causes this query to fail (SQLITE_NOTADB).
    ///    On failure we return [`DbError::DbDecryptionFailed`].
    ///
    /// # Arguments
    /// * `path` — Filesystem path for the SQLite database file (created if absent).
    /// * `key`  — 32-byte key derived from the user passphrase via Argon2id.
    ///            Obtain via [`crate::db::encryption::derive_key`] or
    ///            [`crate::db::encryption::derive_key_from_sidecar`].
    #[cfg(feature = "mobile-sqlite")]
    pub fn open(&mut self, path: &Path, key: &[u8; 32]) -> Result<(), CoreError> {
        let conn = Connection::open(path)
            .map_err(|e| CoreError::Db(DbError::ConnectionFailed(format!("SQLite open: {e}"))))?;

        // Build and execute the SQLCipher PRAGMA key — must be the very first statement.
        let hex: String = key.iter().map(|b| format!("{b:02x}")).collect();
        let pragma = format!("PRAGMA key = \"x'{hex}'\"");
        conn.execute_batch(&pragma)
            .map_err(|e| CoreError::Db(DbError::ConnectionFailed(format!("PRAGMA key: {e}"))))?;

        // Sanity query: verifies key correctness. Fails with SQLITE_NOTADB on wrong key.
        conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
            row.get::<_, i64>(0)
        })
        .map_err(|_| CoreError::Db(DbError::DbDecryptionFailed))?;

        // Auto-load sqlite-vec extension.
        //
        // sqlite-vec is compiled into the binary via build.rs (S04.T01). The
        // entry-point symbol `sqlite3_vec_init` is registered via
        // `sqlite3_auto_extension` so it is available on every connection
        // opened after this point. We call it explicitly here (post-PRAGMA key)
        // so the extension sees the decrypted schema.
        //
        // Safety: `sqlite3_vec_init` is a standard SQLite extension entry
        // point. It does not dereference user memory — it only registers
        // virtual table modules with the connection. The `extern "C"` linkage
        // is sound because sqlite3_vec_init is compiled from C with that ABI.
        #[cfg(feature = "mobile-sqlite")]
        {
            extern "C" {
                fn sqlite3_vec_init(
                    db: *mut std::ffi::c_void,
                    pz_err_msg: *mut *mut std::os::raw::c_char,
                    p_api: *const std::ffi::c_void,
                ) -> std::os::raw::c_int;
            }
            // Register the extension so it auto-loads on every future connection.
            // SQLITE_OK == 0; any non-zero return means registration failed.
            let rc = unsafe {
                rusqlite::ffi::sqlite3_auto_extension(Some(std::mem::transmute(
                    sqlite3_vec_init as *const (),
                )))
            };
            if rc != 0 {
                return Err(CoreError::Db(DbError::ConnectionFailed(format!(
                    "sqlite3_auto_extension(sqlite3_vec_init) failed: rc={rc}"
                ))));
            }
        }

        self.conn = Some(conn);
        Ok(())
    }

    /// Stub open for non-mobile builds (feature not enabled).
    #[cfg(not(feature = "mobile-sqlite"))]
    pub fn open(&mut self, _path: &Path, _key: &[u8; 32]) -> Result<(), CoreError> {
        Err(CoreError::Other(
            "mobile-sqlite feature not enabled at compile time".into(),
        ))
    }

    /// Return the engine identifier string (for diagnostics / logging).
    pub fn engine_name(&self) -> &'static str {
        "sqlite+sqlcipher"
    }
}

impl Default for MobileSqliteEngine {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// MobileDb — thin public wrapper
// ---------------------------------------------------------------------------

/// Mobile database wrapper exposing the SQLCipher-backed SQLite engine.
pub struct MobileDb {
    engine: MobileSqliteEngine,
}

impl MobileDb {
    /// Create a new, unopened mobile database instance.
    pub fn new() -> Self {
        Self {
            engine: MobileSqliteEngine::new(),
        }
    }

    /// Open the encrypted database at `path` using the supplied 32-byte key.
    ///
    /// See [`MobileSqliteEngine::open`] for the full open + PRAGMA key + sanity
    /// check sequence and error semantics.
    pub fn open(&mut self, path: &Path, key: &[u8; 32]) -> Result<(), CoreError> {
        self.engine.open(path, key)
    }

    /// Return the engine identifier string (for diagnostics / logging).
    pub fn engine_name(&self) -> &'static str {
        self.engine.engine_name()
    }
}

impl Default for MobileDb {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(all(test, feature = "mobile-sqlite"))]
mod tests {
    use super::*;
    use crate::db::encryption::{derive_key, KdfProfile};
    use tempfile::tempdir;

    const PASS: &[u8] = b"test_passphrase";
    const SALT: &[u8] = b"test_salt_stable";

    fn test_key() -> [u8; 32] {
        derive_key(PASS, SALT, KdfProfile::MobileStd).expect("derive_key in test")
    }

    fn wrong_key() -> [u8; 32] {
        derive_key(b"wrong_passphrase", SALT, KdfProfile::MobileStd).expect("wrong key in test")
    }

    /// Happy path: open with key, write a row, close, reopen with same key, read back.
    #[test]
    fn test_open_write_close_reopen_read() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("test_enc.db");
        let key = test_key();

        // First open — creates the encrypted DB.
        let mut engine = MobileSqliteEngine::new();
        engine.open(&db_path, &key).expect("first open");

        // Write a row.
        {
            let conn = engine.conn.as_ref().expect("conn present");
            conn.execute_batch(
                "CREATE TABLE kv (id INTEGER PRIMARY KEY, val TEXT NOT NULL);
                 INSERT INTO kv (id, val) VALUES (1, 'hello_encrypted');",
            )
            .expect("create + insert");
        }

        // Drop the engine (closes the connection).
        drop(engine);

        // Reopen with the same key.
        let mut engine2 = MobileSqliteEngine::new();
        engine2.open(&db_path, &key).expect("second open");

        // Read the row back.
        let val: String = engine2
            .conn
            .as_ref()
            .expect("conn present")
            .query_row("SELECT val FROM kv WHERE id = 1", [], |row| row.get(0))
            .expect("select row");

        assert_eq!(val, "hello_encrypted");
    }

    /// Wrong key: opening an existing encrypted DB with a different key returns DbDecryptionFailed.
    #[test]
    fn test_open_wrong_key_returns_decryption_error() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("test_wrongkey.db");
        let key = test_key();

        // Create the DB with the correct key.
        let mut engine = MobileSqliteEngine::new();
        engine.open(&db_path, &key).expect("create with correct key");
        engine
            .conn
            .as_ref()
            .expect("conn")
            .execute_batch("CREATE TABLE t (x INTEGER);")
            .expect("create table");
        drop(engine);

        // Attempt to reopen with the wrong key.
        let mut engine2 = MobileSqliteEngine::new();
        let result = engine2.open(&db_path, &wrong_key());

        match result {
            Err(CoreError::Db(DbError::DbDecryptionFailed)) => { /* expected */ }
            other => panic!("expected DbDecryptionFailed, got {other:?}"),
        }
    }

    /// Engine name is reported correctly.
    #[test]
    fn test_engine_name() {
        let engine = MobileSqliteEngine::new();
        assert_eq!(engine.engine_name(), "sqlite+sqlcipher");
    }

    /// MobileDb wrapper delegates correctly.
    #[test]
    fn test_mobile_db_open_and_name() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("mobiledb.db");
        let key = test_key();

        let mut db = MobileDb::new();
        db.open(&db_path, &key).expect("MobileDb::open");
        assert_eq!(db.engine_name(), "sqlite+sqlcipher");
    }
}
