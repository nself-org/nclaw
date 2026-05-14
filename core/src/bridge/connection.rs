//! Connection state monitoring.
//!
//! S19.T06: Tracks network connectivity and backend health. Allows the router
//! to gracefully degrade when connectivity is impaired.

use crate::bridge::router::ConnectionState;
use std::sync::atomic::{AtomicU8, Ordering};

/// Monitors connection state: Online, Degraded, or Offline.
///
/// Uses an atomic u8 internally where:
/// - 0 = Offline
/// - 1 = Online
/// - 2 = Degraded
pub struct ConnectionMonitor {
    state: AtomicU8,
}

impl ConnectionMonitor {
    /// Create a new monitor in the Offline state.
    pub fn new() -> Self {
        Self {
            state: AtomicU8::new(0),
        }
    }

    /// Create a new monitor in the specified initial state.
    pub fn with_initial_state(initial: ConnectionState) -> Self {
        let monitor = Self::new();
        monitor.set(initial);
        monitor
    }

    /// Get the current connection state.
    pub fn state(&self) -> ConnectionState {
        match self.state.load(Ordering::Acquire) {
            1 => ConnectionState::Online,
            2 => ConnectionState::Degraded,
            _ => ConnectionState::Offline,
        }
    }

    /// Set the connection state.
    pub fn set(&self, state: ConnectionState) {
        let encoded = match state {
            ConnectionState::Offline => 0,
            ConnectionState::Online => 1,
            ConnectionState::Degraded => 2,
        };
        self.state.store(encoded, Ordering::Release);
    }

    /// Check if connection is online (for convenience).
    pub fn is_online(&self) -> bool {
        self.state.load(Ordering::Acquire) == 1
    }

    /// Check if connection is degraded (for convenience).
    pub fn is_degraded(&self) -> bool {
        self.state.load(Ordering::Acquire) == 2
    }

    /// Check if connection is offline (for convenience).
    pub fn is_offline(&self) -> bool {
        self.state.load(Ordering::Acquire) == 0
    }
}

impl Default for ConnectionMonitor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connection_monitor_default_offline() {
        let monitor = ConnectionMonitor::new();
        assert_eq!(monitor.state(), ConnectionState::Offline);
        assert!(monitor.is_offline());
        assert!(!monitor.is_online());
        assert!(!monitor.is_degraded());
    }

    #[test]
    fn connection_monitor_set_online() {
        let monitor = ConnectionMonitor::new();
        monitor.set(ConnectionState::Online);
        assert_eq!(monitor.state(), ConnectionState::Online);
        assert!(monitor.is_online());
        assert!(!monitor.is_offline());
    }

    #[test]
    fn connection_monitor_set_degraded() {
        let monitor = ConnectionMonitor::new();
        monitor.set(ConnectionState::Degraded);
        assert_eq!(monitor.state(), ConnectionState::Degraded);
        assert!(monitor.is_degraded());
        assert!(!monitor.is_online());
        assert!(!monitor.is_offline());
    }

    #[test]
    fn connection_monitor_transitions() {
        let monitor = ConnectionMonitor::with_initial_state(ConnectionState::Online);
        assert!(monitor.is_online());
        monitor.set(ConnectionState::Degraded);
        assert!(monitor.is_degraded());
        monitor.set(ConnectionState::Offline);
        assert!(monitor.is_offline());
        monitor.set(ConnectionState::Online);
        assert!(monitor.is_online());
    }
}
