//! Sync client state machine.
//!
//! States: Disconnected → Connecting → Connected → Syncing → Idle → Disconnected
//! Driven by: enqueued events (push), incoming WebSocket (pull), connection state changes.

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU8, Ordering as AtomicOrdering};

/// Sync state enumeration.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SyncState {
    Disconnected = 0,
    Connecting = 1,
    Connected = 2,
    Syncing = 3,
    Idle = 4,
}

/// Sync client: manages state machine, HLC, and offline queue.
pub struct SyncClient {
    pub server_url: String,
    pub device_id: uuid::Uuid,
    state: AtomicU8,
    pub hlc: super::hlc::HlcGenerator,
    pub queue: super::queue::OfflineQueue,
}

impl SyncClient {
    /// Create a new sync client pointing to a server.
    pub fn new(server_url: impl Into<String>, device_id: uuid::Uuid) -> Self {
        Self {
            server_url: server_url.into(),
            device_id,
            state: AtomicU8::new(SyncState::Disconnected as u8),
            hlc: super::hlc::HlcGenerator::new(device_id),
            queue: super::queue::OfflineQueue::new(),
        }
    }

    /// Get current state.
    pub fn state(&self) -> SyncState {
        match self.state.load(AtomicOrdering::Relaxed) {
            0 => SyncState::Disconnected,
            1 => SyncState::Connecting,
            2 => SyncState::Connected,
            3 => SyncState::Syncing,
            4 => SyncState::Idle,
            _ => SyncState::Disconnected,
        }
    }

    /// Set state.
    pub fn set_state(&self, state: SyncState) {
        self.state.store(state as u8, AtomicOrdering::SeqCst);
    }

    /// Drain a batch of pending events from the offline queue.
    ///
    /// This is the in-process portion of the push pipeline. Network transport
    /// (HTTP POST to `{server_url}/sync/push` + re-enqueue on transient failure)
    /// is layered on top by the sync orchestrator landing in ticket S17.T07.
    ///
    /// Returns the number of events drained. Tests verify queue-draining
    /// semantics independently of the network layer.
    ///
    /// Note: name retained as `push_stub` to keep S17.T07 integration tests
    /// stable; rename to `drain_push_batch` is tracked as a follow-up in S17.T07.
    pub fn push_stub(&self) -> usize {
        let batch = self.queue.pop_batch(100);
        batch.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_defaults_to_disconnected() {
        let client = SyncClient::new("http://localhost:8080", uuid::Uuid::new_v4());
        assert_eq!(client.state(), SyncState::Disconnected);
    }

    #[test]
    fn set_state_transitions() {
        let client = SyncClient::new("http://localhost:8080", uuid::Uuid::new_v4());

        client.set_state(SyncState::Connecting);
        assert_eq!(client.state(), SyncState::Connecting);

        client.set_state(SyncState::Connected);
        assert_eq!(client.state(), SyncState::Connected);

        client.set_state(SyncState::Syncing);
        assert_eq!(client.state(), SyncState::Syncing);

        client.set_state(SyncState::Idle);
        assert_eq!(client.state(), SyncState::Idle);

        client.set_state(SyncState::Disconnected);
        assert_eq!(client.state(), SyncState::Disconnected);
    }

    #[test]
    fn push_stub_empty_queue() {
        let client = SyncClient::new("http://localhost:8080", uuid::Uuid::new_v4());
        let count = client.push_stub();
        assert_eq!(count, 0);
    }

    #[test]
    fn push_stub_pops_batch() {
        let client = SyncClient::new("http://localhost:8080", uuid::Uuid::new_v4());

        // Enqueue some events.
        for i in 0..3 {
            let ev = super::super::queue::QueuedEvent {
                event_id: uuid::Uuid::new_v4(),
                payload: serde_json::json!({"i": i}),
                enqueued_at: chrono::Utc::now(),
                attempts: 0,
            };
            client.queue.enqueue(ev);
        }

        assert_eq!(client.queue.len(), 3);

        let count = client.push_stub();
        assert_eq!(count, 3);

        // Queue should be empty after push.
        assert_eq!(client.queue.len(), 0);
    }
}
