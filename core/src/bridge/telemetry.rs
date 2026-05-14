//! Telemetry hooks for bridge routing decisions.
//!
//! S19.T08: Atomic counters tracking route decisions (local, ServerMux, frontier)
//! and fallback occurrences. No I/O, no allocations — just counters.

use std::sync::atomic::{AtomicU64, Ordering};

/// Atomic telemetry counters for the bridge routing engine.
pub struct BridgeTelemetry {
    /// Count of routing decisions that chose Local.
    local_route_count: AtomicU64,
    /// Count of routing decisions that chose ServerMux.
    server_mux_route_count: AtomicU64,
    /// Count of routing decisions that chose DirectFrontier.
    frontier_route_count: AtomicU64,
    /// Count of fallback/retry occurrences.
    fallback_count: AtomicU64,
}

impl BridgeTelemetry {
    /// Create a new telemetry collector.
    pub fn new() -> Self {
        Self {
            local_route_count: AtomicU64::new(0),
            server_mux_route_count: AtomicU64::new(0),
            frontier_route_count: AtomicU64::new(0),
            fallback_count: AtomicU64::new(0),
        }
    }

    /// Increment the local route counter.
    pub fn record_local_route(&self) {
        self.local_route_count
            .fetch_add(1, Ordering::SeqCst);
    }

    /// Increment the ServerMux route counter.
    pub fn record_server_mux_route(&self) {
        self.server_mux_route_count
            .fetch_add(1, Ordering::SeqCst);
    }

    /// Increment the frontier route counter.
    pub fn record_frontier_route(&self) {
        self.frontier_route_count
            .fetch_add(1, Ordering::SeqCst);
    }

    /// Increment the fallback counter.
    pub fn record_fallback(&self) {
        self.fallback_count.fetch_add(1, Ordering::SeqCst);
    }

    /// Get current count for local routes.
    pub fn local_routes(&self) -> u64 {
        self.local_route_count.load(Ordering::SeqCst)
    }

    /// Get current count for ServerMux routes.
    pub fn server_mux_routes(&self) -> u64 {
        self.server_mux_route_count.load(Ordering::SeqCst)
    }

    /// Get current count for frontier routes.
    pub fn frontier_routes(&self) -> u64 {
        self.frontier_route_count.load(Ordering::SeqCst)
    }

    /// Get current count for fallbacks.
    pub fn fallbacks(&self) -> u64 {
        self.fallback_count.load(Ordering::SeqCst)
    }

    /// Get total routing decisions (sum of all route counters).
    pub fn total_routes(&self) -> u64 {
        self.local_routes() + self.server_mux_routes() + self.frontier_routes()
    }

    /// Reset all counters to zero.
    pub fn reset(&self) {
        self.local_route_count.store(0, Ordering::SeqCst);
        self.server_mux_route_count.store(0, Ordering::SeqCst);
        self.frontier_route_count.store(0, Ordering::SeqCst);
        self.fallback_count.store(0, Ordering::SeqCst);
    }

    /// Get a snapshot of all telemetry as a tuple.
    pub fn snapshot(&self) -> (u64, u64, u64, u64) {
        (
            self.local_routes(),
            self.server_mux_routes(),
            self.frontier_routes(),
            self.fallbacks(),
        )
    }
}

impl Default for BridgeTelemetry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn telemetry_increments() {
        let tel = BridgeTelemetry::new();
        tel.record_local_route();
        tel.record_server_mux_route();
        tel.record_frontier_route();
        tel.record_fallback();

        assert_eq!(tel.local_routes(), 1);
        assert_eq!(tel.server_mux_routes(), 1);
        assert_eq!(tel.frontier_routes(), 1);
        assert_eq!(tel.fallbacks(), 1);
        assert_eq!(tel.total_routes(), 3);
    }

    #[test]
    fn telemetry_multiple_increments() {
        let tel = BridgeTelemetry::new();
        for _ in 0..5 {
            tel.record_local_route();
        }
        for _ in 0..3 {
            tel.record_server_mux_route();
        }
        assert_eq!(tel.local_routes(), 5);
        assert_eq!(tel.server_mux_routes(), 3);
        assert_eq!(tel.total_routes(), 8);
    }

    #[test]
    fn telemetry_reset() {
        let tel = BridgeTelemetry::new();
        tel.record_local_route();
        tel.record_fallback();
        tel.reset();
        assert_eq!(tel.local_routes(), 0);
        assert_eq!(tel.fallbacks(), 0);
    }

    #[test]
    fn telemetry_snapshot() {
        let tel = BridgeTelemetry::new();
        tel.record_local_route();
        tel.record_server_mux_route();
        tel.record_server_mux_route();
        tel.record_frontier_route();
        let (local, mux, frontier, fallback) = tel.snapshot();
        assert_eq!(local, 1);
        assert_eq!(mux, 2);
        assert_eq!(frontier, 1);
        assert_eq!(fallback, 0);
    }

    #[test]
    fn telemetry_default() {
        let tel = BridgeTelemetry::default();
        assert_eq!(tel.total_routes(), 0);
    }
}
