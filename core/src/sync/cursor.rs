//! Per-device sync cursor persistence.
//!
//! Tracks the HLC cursor (wall_ms, lamport) for each device to enable resumption
//! of sync after reconnection. Cursor is persisted to local database.

use crate::error::CoreError;
use serde::{Deserialize, Serialize};

use super::hlc::Hlc;

/// Cursor state for a device — where it left off in the sync stream.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Cursor {
    /// Wall time (milliseconds since epoch) of the last processed event.
    pub wall_ms: i64,
    /// Lamport counter of the last processed event.
    pub lamport: u64,
}

impl Cursor {
    /// Create a new cursor at a given HLC position.
    pub fn new(wall_ms: i64, lamport: u64) -> Self {
        Self { wall_ms, lamport }
    }

    /// Create a cursor from an HLC (discarding device_id).
    pub fn from_hlc(hlc: &Hlc) -> Self {
        Self {
            wall_ms: hlc.wall_ms,
            lamport: hlc.lamport,
        }
    }

    /// Convert cursor back to an HLC for use in sync protocol.
    /// Returns a dummy device_id (zeros) since cursor does not store it.
    pub fn to_hlc(&self) -> Hlc {
        Hlc {
            wall_ms: self.wall_ms,
            lamport: self.lamport,
            device_id: uuid::Uuid::nil(), // Placeholder — should be filled by caller if needed
        }
    }
}

/// Stub interface for saving and loading cursors from the database.
/// Real implementation would delegate to a DAL (Data Access Layer) trait.

/// Save a cursor to local persistent storage.
///
/// Stub implementation. Real usage would call something like:
/// `db.save_cursor(&device_id, &cursor).await`
///
/// Note: Real implementation will be async; this is a stub placeholder.
pub fn save_cursor(device_id: &uuid::Uuid, cursor: &Cursor) -> Result<(), CoreError> {
    // Stub: would write to sqlite / postgres via DAL
    let _json = serde_json::to_string(&cursor)?;
    // Real: db.execute("INSERT OR REPLACE INTO cursors (device_id, cursor_json) VALUES (?, ?)")
    let _ = device_id;
    Ok(()) // For now, assume success
}

/// Load a cursor from local persistent storage.
///
/// Returns None if no cursor exists for the device (first sync ever).
/// Stub implementation. Real usage would call something like:
/// `db.load_cursor(&device_id).await`
///
/// Note: Real implementation will be async; this is a stub placeholder.
pub fn load_cursor(device_id: &uuid::Uuid) -> Result<Option<Cursor>, CoreError> {
    // Stub: would read from sqlite / postgres via DAL
    // Real: db.query_one("SELECT cursor_json FROM cursors WHERE device_id = ?")
    let _ = device_id;
    Ok(None) // Stub: no cursor found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursor_from_hlc_preserves_values() {
        let hlc = Hlc {
            wall_ms: 1000,
            lamport: 42,
            device_id: uuid::Uuid::new_v4(),
        };
        let cursor = Cursor::from_hlc(&hlc);
        assert_eq!(cursor.wall_ms, 1000);
        assert_eq!(cursor.lamport, 42);
    }

    #[test]
    fn cursor_to_hlc_roundtrip() {
        let cursor = Cursor::new(5000, 100);
        let hlc = cursor.to_hlc();
        assert_eq!(hlc.wall_ms, 5000);
        assert_eq!(hlc.lamport, 100);
    }

    #[test]
    fn cursor_serializes() {
        let cursor = Cursor::new(2000, 50);
        let json = serde_json::to_string(&cursor).expect("serialize");
        assert!(json.contains("\"wall_ms\":2000"));
        assert!(json.contains("\"lamport\":50"));
    }

    #[tokio::test]
    async fn stub_save_cursor_succeeds() {
        let device_id = uuid::Uuid::new_v4();
        let cursor = Cursor::new(1000, 10);
        let result = save_cursor(&device_id, &cursor).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn stub_load_cursor_returns_none() {
        let device_id = uuid::Uuid::new_v4();
        let result = load_cursor(&device_id).await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_none());
    }
}
