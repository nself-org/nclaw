//! Batching policy for event transmission.
//!
//! Determines when to flush accumulated events to the server based on:
//! - Batch size (max event count)
//! - Batch bytes (max serialized size)
//! - Batch age (max time since first event in batch)

use serde::{Deserialize, Serialize};

/// Batching policy configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchPolicy {
    /// Maximum number of events per batch.
    pub max_batch_size: u32,
    /// Maximum serialized bytes per batch.
    pub max_batch_bytes: u64,
    /// Maximum time to hold events before flushing (milliseconds).
    pub max_wait_ms: u64,
}

impl Default for BatchPolicy {
    fn default() -> Self {
        Self {
            max_batch_size: 1000,
            max_batch_bytes: 5_000_000, // 5 MB
            max_wait_ms: 30000,         // 30 seconds
        }
    }
}

impl BatchPolicy {
    /// Create a new batch policy with custom limits.
    pub fn new(max_batch_size: u32, max_batch_bytes: u64, max_wait_ms: u64) -> Self {
        Self {
            max_batch_size,
            max_batch_bytes,
            max_wait_ms,
        }
    }

    /// Determine if the batch should be flushed based on current state.
    ///
    /// Flush when ANY of:
    /// - current_size >= max_batch_size
    /// - current_bytes >= max_batch_bytes
    /// - age_ms >= max_wait_ms
    pub fn should_flush(&self, current_size: u32, current_bytes: u64, age_ms: u64) -> bool {
        current_size >= self.max_batch_size
            || current_bytes >= self.max_batch_bytes
            || age_ms >= self.max_wait_ms
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_policy_has_sensible_defaults() {
        let policy = BatchPolicy::default();
        assert_eq!(policy.max_batch_size, 1000);
        assert_eq!(policy.max_batch_bytes, 5_000_000);
        assert_eq!(policy.max_wait_ms, 30000);
    }

    #[test]
    fn should_flush_on_size() {
        let policy = BatchPolicy::new(10, 1_000_000, 60000);
        assert!(!policy.should_flush(9, 100, 1000));
        assert!(policy.should_flush(10, 100, 1000)); // size = max
        assert!(policy.should_flush(11, 100, 1000)); // size > max
    }

    #[test]
    fn should_flush_on_bytes() {
        let policy = BatchPolicy::new(1000, 1000, 60000);
        assert!(!policy.should_flush(100, 999, 1000));
        assert!(policy.should_flush(100, 1000, 1000)); // bytes = max
        assert!(policy.should_flush(100, 1001, 1000)); // bytes > max
    }

    #[test]
    fn should_flush_on_age() {
        let policy = BatchPolicy::new(1000, 1_000_000, 5000);
        assert!(!policy.should_flush(100, 100, 4999));
        assert!(policy.should_flush(100, 100, 5000)); // age = max
        assert!(policy.should_flush(100, 100, 5001)); // age > max
    }

    #[test]
    fn should_not_flush_when_all_under_limit() {
        let policy = BatchPolicy::new(100, 10_000, 30000);
        assert!(!policy.should_flush(50, 5000, 15000));
    }
}
