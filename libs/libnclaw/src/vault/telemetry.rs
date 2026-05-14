//! Vault telemetry — counters for vault operations and device lifecycle events

use std::sync::atomic::{AtomicU64, Ordering};

/// Telemetry counters for vault operations
pub struct VaultTelemetry {
    pub envelopes_sealed: AtomicU64,
    pub envelopes_opened: AtomicU64,
    pub devices_registered: AtomicU64,
    pub devices_revoked: AtomicU64,
}

impl VaultTelemetry {
    /// Create a new telemetry instance with all counters at zero.
    pub fn new() -> Self {
        VaultTelemetry {
            envelopes_sealed: AtomicU64::new(0),
            envelopes_opened: AtomicU64::new(0),
            devices_registered: AtomicU64::new(0),
            devices_revoked: AtomicU64::new(0),
        }
    }

    /// Increment the sealed-envelopes counter.
    pub fn inc_sealed(&self) {
        self.envelopes_sealed.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment the opened-envelopes counter.
    pub fn inc_opened(&self) {
        self.envelopes_opened.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment the registered-devices counter.
    pub fn inc_registered(&self) {
        self.devices_registered.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment the revoked-devices counter.
    pub fn inc_revoked(&self) {
        self.devices_revoked.fetch_add(1, Ordering::Relaxed);
    }

    /// Get a snapshot of all counters.
    pub fn snapshot(&self) -> VaultTelemetrySnapshot {
        VaultTelemetrySnapshot {
            envelopes_sealed: self.envelopes_sealed.load(Ordering::Relaxed),
            envelopes_opened: self.envelopes_opened.load(Ordering::Relaxed),
            devices_registered: self.devices_registered.load(Ordering::Relaxed),
            devices_revoked: self.devices_revoked.load(Ordering::Relaxed),
        }
    }
}

impl Default for VaultTelemetry {
    fn default() -> Self {
        Self::new()
    }
}

/// Telemetry snapshot — immutable point-in-time counters
#[derive(Debug, Clone)]
pub struct VaultTelemetrySnapshot {
    pub envelopes_sealed: u64,
    pub envelopes_opened: u64,
    pub devices_registered: u64,
    pub devices_revoked: u64,
}
