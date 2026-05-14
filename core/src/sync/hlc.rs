//! Hybrid Logical Clock per nclaw/protocol/sync-protocol.md §3.
//!
//! The HLC combines wall time with a logical counter to provide total event ordering
//! that respects causality even across clock-skewed devices.

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering as AtomicOrdering};
use std::time::{SystemTime, UNIX_EPOCH};

/// HybridLogicalClock: (wall_ms, lamport, device_id) with total order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Hlc {
    pub wall_ms: i64,
    pub lamport: u64,
    pub device_id: uuid::Uuid,
}

/// Generator maintains HLC state and produces ordered timestamps for local and received events.
pub struct HlcGenerator {
    device_id: uuid::Uuid,
    wall_ms: AtomicI64,
    lamport: AtomicU64,
}

impl HlcGenerator {
    /// Create a new HLC generator for a device.
    pub fn new(device_id: uuid::Uuid) -> Self {
        Self {
            device_id,
            wall_ms: AtomicI64::new(0),
            lamport: AtomicU64::new(0),
        }
    }

    /// Generate next HLC for a local event.
    ///
    /// Rule (§3.2): If now > hlc.wall_ms, reset lamport to 0. Otherwise increment.
    pub fn tick(&self) -> Hlc {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);

        let prev_wall = self.wall_ms.load(AtomicOrdering::Relaxed);
        let new_wall = now_ms.max(prev_wall);

        let new_lamport = if new_wall > prev_wall {
            // Wall time advanced; reset lamport counter.
            self.wall_ms.store(new_wall, AtomicOrdering::SeqCst);
            self.lamport.store(0, AtomicOrdering::SeqCst);
            0
        } else {
            // Wall time didn't advance; increment counter.
            self.lamport.fetch_add(1, AtomicOrdering::SeqCst)
        };

        Hlc {
            wall_ms: new_wall,
            lamport: new_lamport,
            device_id: self.device_id,
        }
    }

    /// Merge an incoming HLC into local state.
    ///
    /// Rule (§3.2): new_wall = max(hlc.wall_ms, recv_wall, now). Update lamport based on
    /// which wall times are equal. Guarantees: local HLC strictly > incoming HLC.
    pub fn merge(&self, incoming: &Hlc) -> Hlc {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);

        let prev_wall = self.wall_ms.load(AtomicOrdering::Relaxed);
        let prev_lamport = self.lamport.load(AtomicOrdering::Relaxed);

        let new_wall = [prev_wall, incoming.wall_ms, now_ms]
            .iter()
            .max()
            .copied()
            .unwrap_or(0);

        let new_lamport = if new_wall == prev_wall && new_wall == incoming.wall_ms {
            // All three wall times equal: take max of local and incoming lamport + 1.
            prev_lamport.max(incoming.lamport) + 1
        } else if new_wall == incoming.wall_ms {
            // Incoming wall time wins: increment its lamport.
            incoming.lamport + 1
        } else if new_wall == prev_wall {
            // Local wall time wins: increment local lamport.
            prev_lamport + 1
        } else {
            // Now is strictly newer: reset lamport.
            0
        };

        self.wall_ms.store(new_wall, AtomicOrdering::SeqCst);
        self.lamport.store(new_lamport, AtomicOrdering::SeqCst);

        Hlc {
            wall_ms: new_wall,
            lamport: new_lamport,
            device_id: self.device_id,
        }
    }
}

/// Total order: wall_ms → lamport → device_id (lexicographic).
impl PartialOrd for Hlc {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Hlc {
    fn cmp(&self, other: &Self) -> Ordering {
        self.wall_ms
            .cmp(&other.wall_ms)
            .then(self.lamport.cmp(&other.lamport))
            .then(self.device_id.cmp(&other.device_id))
    }
}

impl Default for HlcGenerator {
    fn default() -> Self {
        Self::new(uuid::Uuid::new_v4())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tick_monotonically_increasing() {
        let gen = HlcGenerator::new(uuid::Uuid::nil());
        let h1 = gen.tick();
        let h2 = gen.tick();
        let h3 = gen.tick();
        assert!(h1 < h2);
        assert!(h2 < h3);
    }

    #[test]
    fn merge_with_later_wall_ms_updates() {
        let gen = HlcGenerator::new(uuid::Uuid::nil());
        let other_id = uuid::Uuid::new_v4();
        let incoming = Hlc {
            wall_ms: 2000,
            lamport: 5,
            device_id: other_id,
        };
        let merged = gen.merge(&incoming);
        assert_eq!(merged.wall_ms, 2000);
        assert_eq!(merged.lamport, 6); // incoming.lamport + 1
        assert_eq!(merged.device_id, gen.device_id);
    }

    #[test]
    fn hlc_total_order() {
        let dev_a = uuid::Uuid::new_v4();
        let dev_b = uuid::Uuid::new_v4();
        // Ensure consistent ordering of device IDs for test.
        let (dev_early, dev_late) = if dev_a < dev_b {
            (dev_a, dev_b)
        } else {
            (dev_b, dev_a)
        };

        let h1 = Hlc {
            wall_ms: 1000,
            lamport: 0,
            device_id: dev_early,
        };
        let h2 = Hlc {
            wall_ms: 1000,
            lamport: 1,
            device_id: dev_early,
        };
        let h3 = Hlc {
            wall_ms: 1000,
            lamport: 0,
            device_id: dev_late,
        };
        let h4 = Hlc {
            wall_ms: 2000,
            lamport: 0,
            device_id: dev_early,
        };

        assert!(h1 < h2, "same wall, lower lamport wins");
        assert!(h2 < h3, "same wall/lamport, lexicographic device_id wins");
        assert!(h3 < h4, "higher wall_ms wins");
    }

    #[test]
    fn merge_equal_wall_times() {
        let dev_a = uuid::Uuid::new_v4();
        let dev_b = uuid::Uuid::new_v4();
        let gen = HlcGenerator::new(dev_a);

        // Artificially set the generator's wall_ms to 1000.
        gen.wall_ms.store(1000, AtomicOrdering::SeqCst);
        gen.lamport.store(3, AtomicOrdering::SeqCst);

        let incoming = Hlc {
            wall_ms: 1000,
            lamport: 5,
            device_id: dev_b,
        };

        let merged = gen.merge(&incoming);
        assert_eq!(merged.wall_ms, 1000);
        // max(3, 5) + 1 = 6
        assert_eq!(merged.lamport, 6);
    }
}
