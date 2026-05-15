//! Snapshot protocol for device bootstrap.
//!
//! When a new device joins the sync network, it requests a snapshot containing
//! all events from a given HLC watermark. The server responds with the full state
//! so the device can apply recent events and catch up to the current cursor.

use crate::error::CoreError;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::hlc::Hlc;
use super::lww::EventEnvelope;

/// Request a snapshot of events since a given HLC.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotRequest {
    /// Device ID requesting the snapshot.
    pub device_id: Uuid,
    /// HLC watermark: return events with hlc > since_hlc.
    pub since_hlc: Option<Hlc>,
}

/// Server response containing events and updated cursor state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotResponse {
    /// Ordered list of events to apply.
    pub events: Vec<EventEnvelope>,
    /// Server's current cursor (wall_ms, lamport) — device advances to this.
    pub cursor: Option<Hlc>,
}

impl SnapshotRequest {
    /// Create a new snapshot request for a device, optionally starting from an HLC watermark.
    pub fn new(device_id: Uuid, since_hlc: Option<Hlc>) -> Self {
        Self {
            device_id,
            since_hlc,
        }
    }
}

impl SnapshotResponse {
    /// Create a new snapshot response with events and cursor.
    pub fn new(events: Vec<EventEnvelope>, cursor: Option<Hlc>) -> Self {
        Self { events, cursor }
    }

    /// Check if the snapshot is empty (no events to apply).
    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }
}

/// Request a snapshot from the sync network during device bootstrap.
///
/// Returns `CoreError::NotImplemented` until ticket S17.T07 wires this to
/// `SyncNetwork::get("/sync/snapshot")`. The request envelope is validated
/// via serde so callers can rely on the schema today.
pub fn request_snapshot(
    device_id: Uuid,
    since_hlc: Option<Hlc>,
) -> Result<SnapshotResponse, CoreError> {
    let req = SnapshotRequest::new(device_id, since_hlc);
    let _json = serde_json::to_string(&req)?;
    Err(CoreError::NotImplemented(
        "request_snapshot pending S17.T07 network-layer integration".to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_request_serializes() {
        let device_id = Uuid::new_v4();
        let req = SnapshotRequest::new(device_id, None);
        let json = serde_json::to_string(&req).expect("serialize");
        assert!(json.contains(device_id.to_string().as_str()));
    }

    #[test]
    fn snapshot_response_is_empty_when_no_events() {
        let resp = SnapshotResponse::new(vec![], None);
        assert!(resp.is_empty());
    }
}
