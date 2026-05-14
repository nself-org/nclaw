//! Sync telemetry and metrics collection.
//!
//! Tracks sync performance metrics: events pushed/pulled, failures, and cursor lag.
//! Used for debugging, monitoring, and performance analysis.

use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Sync telemetry counters — all atomic for thread-safe concurrent updates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncTelemetry {
    /// Number of events successfully pushed to server.
    pub events_pushed: Arc<AtomicU64>,
    /// Number of events successfully pulled from server.
    pub events_pulled: Arc<AtomicU64>,
    /// Number of failed push attempts.
    pub push_failures: Arc<AtomicU64>,
    /// Number of failed pull attempts.
    pub pull_failures: Arc<AtomicU64>,
    /// Current lag between local cursor and server cursor (milliseconds).
    pub current_cursor_lag_ms: Arc<AtomicU64>,
}

impl Default for SyncTelemetry {
    fn default() -> Self {
        Self::new()
    }
}

impl SyncTelemetry {
    /// Create a new telemetry instance with all counters at zero.
    pub fn new() -> Self {
        Self {
            events_pushed: Arc::new(AtomicU64::new(0)),
            events_pulled: Arc::new(AtomicU64::new(0)),
            push_failures: Arc::new(AtomicU64::new(0)),
            pull_failures: Arc::new(AtomicU64::new(0)),
            current_cursor_lag_ms: Arc::new(AtomicU64::new(0)),
        }
    }

    /// Increment the events pushed counter.
    pub fn increment_events_pushed(&self) {
        self.events_pushed.fetch_add(1, Ordering::SeqCst);
    }

    /// Increment the events pulled counter.
    pub fn increment_events_pulled(&self) {
        self.events_pulled.fetch_add(1, Ordering::SeqCst);
    }

    /// Increment the push failures counter.
    pub fn increment_push_failures(&self) {
        self.push_failures.fetch_add(1, Ordering::SeqCst);
    }

    /// Increment the pull failures counter.
    pub fn increment_pull_failures(&self) {
        self.pull_failures.fetch_add(1, Ordering::SeqCst);
    }

    /// Set the current cursor lag in milliseconds.
    pub fn set_cursor_lag(&self, lag_ms: u64) {
        self.current_cursor_lag_ms.store(lag_ms, Ordering::SeqCst);
    }

    /// Create a snapshot of current metrics for serialization.
    pub fn snapshot(&self) -> SyncTelemetrySnapshot {
        SyncTelemetrySnapshot {
            events_pushed: self.events_pushed.load(Ordering::SeqCst),
            events_pulled: self.events_pulled.load(Ordering::SeqCst),
            push_failures: self.push_failures.load(Ordering::SeqCst),
            pull_failures: self.pull_failures.load(Ordering::SeqCst),
            current_cursor_lag_ms: self.current_cursor_lag_ms.load(Ordering::SeqCst),
        }
    }
}

/// Serializable snapshot of telemetry metrics at a point in time.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncTelemetrySnapshot {
    pub events_pushed: u64,
    pub events_pulled: u64,
    pub push_failures: u64,
    pub pull_failures: u64,
    pub current_cursor_lag_ms: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_telemetry_starts_at_zero() {
        let telem = SyncTelemetry::new();
        let snap = telem.snapshot();
        assert_eq!(snap.events_pushed, 0);
        assert_eq!(snap.events_pulled, 0);
        assert_eq!(snap.push_failures, 0);
        assert_eq!(snap.pull_failures, 0);
        assert_eq!(snap.current_cursor_lag_ms, 0);
    }

    #[test]
    fn increment_events_pushed() {
        let telem = SyncTelemetry::new();
        telem.increment_events_pushed();
        telem.increment_events_pushed();
        let snap = telem.snapshot();
        assert_eq!(snap.events_pushed, 2);
    }

    #[test]
    fn increment_events_pulled() {
        let telem = SyncTelemetry::new();
        telem.increment_events_pulled();
        let snap = telem.snapshot();
        assert_eq!(snap.events_pulled, 1);
    }

    #[test]
    fn increment_push_failures() {
        let telem = SyncTelemetry::new();
        telem.increment_push_failures();
        telem.increment_push_failures();
        telem.increment_push_failures();
        let snap = telem.snapshot();
        assert_eq!(snap.push_failures, 3);
    }

    #[test]
    fn set_cursor_lag() {
        let telem = SyncTelemetry::new();
        telem.set_cursor_lag(5000);
        let snap = telem.snapshot();
        assert_eq!(snap.current_cursor_lag_ms, 5000);
    }

    #[test]
    fn snapshot_serializes() {
        let snap = SyncTelemetrySnapshot {
            events_pushed: 100,
            events_pulled: 50,
            push_failures: 2,
            pull_failures: 1,
            current_cursor_lag_ms: 3000,
        };
        let json = serde_json::to_string(&snap).expect("serialize");
        assert!(json.contains("\"events_pushed\":100"));
        assert!(json.contains("\"current_cursor_lag_ms\":3000"));
    }
}
