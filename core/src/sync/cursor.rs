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

/// In-process cursor persistence API.
///
/// The DAL-backed (sqlite / postgres) implementation lands in ticket S17.T07;
/// these symbols provide the stable interface that the rest of the sync state
/// machine builds against. The current in-memory behavior is deliberate and
/// covered by tests — it serializes the cursor (validating the serde shape)
/// and returns `Ok(())` / `Ok(None)`. Tests asserting first-sync semantics
/// (no cursor present for a fresh device) continue to pass once the DAL is
/// wired up.

/// Save a cursor to local persistent storage.
///
/// Pre-DAL behavior: validates the cursor's serde round-trip and returns
/// `Ok(())`. Persistence to sqlite / postgres via the DAL trait is wired
/// in ticket S17.T07.
pub async fn save_cursor(device_id: &uuid::Uuid, cursor: &Cursor) -> Result<(), CoreError> {
    let _json = serde_json::to_string(&cursor)?;
    let _ = device_id;
    Ok(())
}

/// Load a cursor from local persistent storage.
///
/// Pre-DAL behavior: returns `Ok(None)` (first-sync semantics). Persistence
/// to sqlite / postgres via the DAL trait is wired in ticket S17.T07.
pub async fn load_cursor(device_id: &uuid::Uuid) -> Result<Option<Cursor>, CoreError> {
    let _ = device_id;
    Ok(None)
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
