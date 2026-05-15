//! WebSocket heartbeat / keep-alive mechanism.
//!
//! Sends periodic ping frames to keep the sync WebSocket alive and detect dead connections.
//! Default interval is 30 seconds.

use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Heartbeat timer configuration and state.
#[derive(Debug, Clone)]
pub struct HeartbeatTimer {
    /// Interval between heartbeat pings in milliseconds.
    pub interval_ms: u64,
}

impl Default for HeartbeatTimer {
    fn default() -> Self {
        Self {
            interval_ms: 30000, // 30 seconds
        }
    }
}

impl HeartbeatTimer {
    /// Create a new heartbeat timer with custom interval.
    pub fn new(interval_ms: u64) -> Self {
        Self { interval_ms }
    }

    /// Get the duration until the next heartbeat tick.
    pub fn next_tick(&self) -> Duration {
        Duration::from_millis(self.interval_ms)
    }

    /// Create a heartbeat ping payload as JSON.
    ///
    /// Format: `{"type":"ping","ts":<ms>}` where ts is system time in milliseconds.
    pub fn ping_payload() -> HeartbeatPing {
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        HeartbeatPing {
            r#type: "ping".to_string(),
            ts: now_ms,
        }
    }
}

/// JSON payload sent as a WebSocket heartbeat ping.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatPing {
    #[serde(rename = "type")]
    pub r#type: String,
    pub ts: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_interval_is_30_seconds() {
        let timer = HeartbeatTimer::default();
        assert_eq!(timer.interval_ms, 30000);
    }

    #[test]
    fn next_tick_returns_duration() {
        let timer = HeartbeatTimer::new(15000);
        let duration = timer.next_tick();
        assert_eq!(duration, Duration::from_millis(15000));
    }

    #[test]
    fn ping_payload_serializes() {
        let ping = HeartbeatTimer::ping_payload();
        let json = serde_json::to_string(&ping).expect("serialize");
        assert!(json.contains("\"type\":\"ping\""));
        assert!(json.contains("\"ts\":"));
    }

    #[test]
    fn heartbeat_timer_custom_interval() {
        let timer = HeartbeatTimer::new(5000);
        assert_eq!(timer.interval_ms, 5000);
    }
}
