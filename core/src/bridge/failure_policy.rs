//! Failure recovery policies: exponential backoff with jitter.
//!
//! S19.T09: Implements exponential backoff with jitter for retry scenarios
//! when frontier APIs or internal services fail. Prevents thundering herd
//! and graceful degradation under load.

use std::time::Duration;

/// Compute the backoff duration for a retry attempt.
///
/// Uses exponential backoff with jitter:
/// - Base: 100ms
/// - Growth: 2^attempt
/// - Max: 60 seconds
/// - Jitter: +0-100ms
///
/// This ensures retries don't pile up at the same time.
pub fn backoff(attempt: u32) -> Duration {
    const BASE_MS: u64 = 100;
    const MAX_MS: u64 = 60_000;

    // Exponential: 100ms * 2^attempt, capped at 10 doublings
    let exp = BASE_MS.saturating_mul(2_u64.saturating_pow(attempt.min(10)));
    let with_cap = exp.min(MAX_MS);

    // Add jitter: 0-100ms
    let jitter = (rand::random::<u64>() % 100) + 1;
    let total = with_cap.saturating_add(jitter);

    Duration::from_millis(total)
}

/// Compute backoff without randomness (for testing).
///
/// Same as `backoff` but always uses maximum jitter (100ms) for determinism.
#[cfg(test)]
pub fn backoff_deterministic(attempt: u32) -> Duration {
    const BASE_MS: u64 = 100;
    const MAX_MS: u64 = 60_000;
    const JITTER_MS: u64 = 100;

    let exp = BASE_MS.saturating_mul(2_u64.saturating_pow(attempt.min(10)));
    let with_cap = exp.min(MAX_MS);
    let total = with_cap.saturating_add(JITTER_MS);

    Duration::from_millis(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_increases_exponentially() {
        let b0 = backoff_deterministic(0).as_millis() as u64;
        let b1 = backoff_deterministic(1).as_millis() as u64;
        let b2 = backoff_deterministic(2).as_millis() as u64;

        // b1 should be roughly 2x b0, b2 should be roughly 2x b1
        assert!(b1 > b0);
        assert!(b2 > b1);

        // Verify base: 100 + 100 (jitter) = 200
        assert_eq!(b0, 200);
    }

    #[test]
    fn backoff_caps_at_max() {
        let b10 = backoff_deterministic(10).as_millis() as u64;
        let b11 = backoff_deterministic(11).as_millis() as u64;

        // Both should cap at 60_000 + 100 (jitter)
        assert_eq!(b10, 60_100);
        assert_eq!(b11, 60_100);
    }

    #[test]
    fn backoff_has_jitter() {
        // Run multiple times; random jitter means different results
        let mut durations = vec![];
        for _ in 0..10 {
            durations.push(backoff(0).as_millis());
        }

        // At least some variance (very unlikely all are identical given rand)
        let unique_count = durations
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len();
        assert!(unique_count > 1, "Jitter should produce variance");
    }

    #[test]
    fn backoff_deterministic_is_consistent() {
        let b1 = backoff_deterministic(3);
        let b2 = backoff_deterministic(3);
        assert_eq!(b1, b2);
    }
}
