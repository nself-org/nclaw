//! Retry policy with exponential backoff and full jitter for the sync client.
//!
//! Bounded retries on transient transport errors (HTTP 429, 503, network/timeout
//! failures). Permanent errors (4xx other than 429, signature/auth/state errors)
//! are NOT retried — they bubble up immediately.
//!
//! ## Backoff
//!
//! Full jitter as described by AWS Architecture Blog
//! ("Exponential Backoff And Jitter", 2015):
//!
//! ```text
//! sleep = random_between(0, min(cap, base * 2^attempt))
//! ```
//!
//! Full jitter (NOT equal jitter or decorrelated jitter) is chosen because it
//! minimizes contention when many clients retry simultaneously after a
//! server-side incident: every client picks a different point in the [0, cap)
//! interval, smoothing the retry storm.
//!
//! Defaults: `base = 200ms`, `factor = 2.0`, `max = 30s`, `max_attempts = 5`.
//!
//! ## `Retry-After`
//!
//! When the server returns HTTP 429 or 503 with a `Retry-After` header (RFC 7231,
//! delta-seconds), the caller-provided value supersedes the computed backoff if
//! it is larger. This honors the server's explicit pacing instruction while
//! still capping waits at [`RetryPolicy::max_delay`].
//!
//! ## WebSocket reconnect
//!
//! HTTP request retries are bounded and short-lived. WebSocket subscribe
//! reconnects need a separate, longer-lived policy (base ~1s, max ~5min,
//! unbounded attempts with jittered cap). That policy lives elsewhere — this
//! module is HTTP-only.

use std::time::Duration;

/// Outcome of classifying an error or HTTP status for retry purposes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RetryDecision {
    /// The operation succeeded or hit a non-retryable terminal error.
    Stop,
    /// The operation hit a transient failure; retry after the supplied delay.
    Retry,
}

/// Retry policy parameters. Constructed via [`RetryPolicy::default`] or
/// [`RetryPolicy::new`] / [`RetryPolicy::builder_like`] helpers.
#[derive(Debug, Clone, Copy)]
pub struct RetryPolicy {
    /// Initial backoff window; the first retry sleeps in `[0, base_delay)`.
    pub base_delay: Duration,
    /// Multiplicative growth factor between attempts (typically `2.0`).
    pub factor: f64,
    /// Hard ceiling for any single sleep. Both the exponential growth and any
    /// honored `Retry-After` value are clamped to this cap.
    pub max_delay: Duration,
    /// Maximum number of attempts INCLUDING the first try. `max_attempts = 5`
    /// means 1 initial call + up to 4 retries.
    pub max_attempts: u32,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            base_delay: Duration::from_millis(200),
            factor: 2.0,
            max_delay: Duration::from_secs(30),
            max_attempts: 5,
        }
    }
}

impl RetryPolicy {
    /// Construct a policy with explicit knobs.
    pub fn new(
        base_delay: Duration,
        factor: f64,
        max_delay: Duration,
        max_attempts: u32,
    ) -> Self {
        Self {
            base_delay,
            factor,
            max_delay,
            max_attempts,
        }
    }

    /// Compute the upper bound of the [0, cap) jitter window for a given
    /// 0-indexed attempt number. The bound grows exponentially and is clamped
    /// to [`Self::max_delay`].
    ///
    /// Attempt 0 corresponds to the FIRST retry (i.e. between attempt 1 and
    /// attempt 2 of the operation).
    pub fn delay_cap(&self, attempt: u32) -> Duration {
        let base_ms = self.base_delay.as_millis() as f64;
        let max_ms = self.max_delay.as_millis() as f64;
        // factor.powi may overflow f64::INFINITY for huge `attempt`; the
        // `.min(max_ms)` clamp handles that case.
        let growth = self.factor.powi(attempt as i32);
        let unclamped = base_ms * growth;
        let clamped = unclamped.min(max_ms).max(0.0);
        Duration::from_millis(clamped as u64)
    }

    /// Pick a jittered sleep in `[0, delay_cap(attempt))` using full jitter.
    ///
    /// The random source is parameter-injected to keep the function pure and
    /// testable. Production callers should pass a `rand::thread_rng()`-derived
    /// uniform `[0.0, 1.0)` value.
    pub fn jittered_delay(&self, attempt: u32, rand_unit: f64) -> Duration {
        let cap_ms = self.delay_cap(attempt).as_millis() as f64;
        // Defensive clamp: callers MUST pass [0.0, 1.0); clamp regardless.
        let unit = rand_unit.clamp(0.0, 1.0);
        let ms = (cap_ms * unit) as u64;
        Duration::from_millis(ms)
    }

    /// Decide whether to keep retrying after `attempt` failed retries. Returns
    /// `Stop` once the budget is exhausted.
    pub fn should_retry(&self, attempt: u32) -> RetryDecision {
        // attempt is the 0-indexed retry number that JUST failed. Total tries
        // so far = attempt + 1 (initial) + retries already done.
        // We allow `max_attempts - 1` retries after the initial try.
        if attempt + 1 < self.max_attempts {
            RetryDecision::Retry
        } else {
            RetryDecision::Stop
        }
    }

    /// Combine a computed jittered backoff with an optional server-supplied
    /// `Retry-After` hint. The hint supersedes the computed value when larger;
    /// the combined result is then clamped to [`Self::max_delay`].
    pub fn merge_retry_after(
        &self,
        computed: Duration,
        retry_after: Option<Duration>,
    ) -> Duration {
        let chosen = match retry_after {
            Some(hint) if hint > computed => hint,
            _ => computed,
        };
        if chosen > self.max_delay {
            self.max_delay
        } else {
            chosen
        }
    }
}

/// Parse an HTTP `Retry-After` header value into a [`Duration`].
///
/// Supports the delta-seconds form (RFC 7231 §7.1.3). The HTTP-date form is
/// recognized but not converted (returns `None`) — servers in this stack are
/// expected to emit integer seconds. A negative or non-numeric value yields
/// `None`.
pub fn parse_retry_after(value: &str) -> Option<Duration> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    // Delta-seconds: a non-negative integer.
    if let Ok(secs) = trimmed.parse::<u64>() {
        return Some(Duration::from_secs(secs));
    }
    // We deliberately do NOT parse HTTP-date here — the nself-sync server
    // always emits integer seconds, and reaching for chrono parsing adds risk
    // without value for this code path.
    None
}

/// Classify an HTTP status code for retry purposes.
///
/// - 5xx and 429 → transient, retry
/// - 408 (Request Timeout) → transient, retry
/// - Other 4xx → permanent, stop
/// - 2xx/3xx → not an error; callers should not invoke this
pub fn is_retryable_status(code: u16) -> bool {
    matches!(code, 408 | 429 | 500..=599)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_policy_matches_spec() {
        let p = RetryPolicy::default();
        assert_eq!(p.base_delay, Duration::from_millis(200));
        assert!((p.factor - 2.0).abs() < f64::EPSILON);
        assert_eq!(p.max_delay, Duration::from_secs(30));
        assert_eq!(p.max_attempts, 5);
    }

    #[test]
    fn delay_cap_grows_exponentially_then_clamps() {
        let p = RetryPolicy::default();
        assert_eq!(p.delay_cap(0), Duration::from_millis(200));
        assert_eq!(p.delay_cap(1), Duration::from_millis(400));
        assert_eq!(p.delay_cap(2), Duration::from_millis(800));
        assert_eq!(p.delay_cap(3), Duration::from_millis(1600));
        // Eventually clamps to max_delay (30s).
        assert_eq!(p.delay_cap(20), Duration::from_secs(30));
        assert_eq!(p.delay_cap(100), Duration::from_secs(30));
    }

    #[test]
    fn jittered_delay_is_within_window() {
        let p = RetryPolicy::default();
        // unit = 0.0 → sleep = 0
        assert_eq!(p.jittered_delay(0, 0.0), Duration::ZERO);
        // unit = 0.999 → sleep just under cap
        let nearly_full = p.jittered_delay(0, 0.999);
        assert!(nearly_full <= Duration::from_millis(200));
        assert!(nearly_full > Duration::from_millis(150));
        // unit clamped to [0,1)
        let over = p.jittered_delay(0, 2.5);
        assert!(over <= Duration::from_millis(200));
    }

    #[test]
    fn should_retry_respects_max_attempts() {
        let p = RetryPolicy::default(); // max_attempts = 5
        assert_eq!(p.should_retry(0), RetryDecision::Retry); // after 1st failure
        assert_eq!(p.should_retry(1), RetryDecision::Retry);
        assert_eq!(p.should_retry(2), RetryDecision::Retry);
        assert_eq!(p.should_retry(3), RetryDecision::Retry); // 4 retries used, 1 left? no — see below
        assert_eq!(p.should_retry(4), RetryDecision::Stop);  // 5 attempts total reached
        assert_eq!(p.should_retry(99), RetryDecision::Stop);
    }

    #[test]
    fn retry_after_supersedes_smaller_computed() {
        let p = RetryPolicy::default();
        let merged = p.merge_retry_after(Duration::from_millis(100), Some(Duration::from_secs(2)));
        assert_eq!(merged, Duration::from_secs(2));
    }

    #[test]
    fn retry_after_does_not_override_larger_computed() {
        let p = RetryPolicy::default();
        let merged = p.merge_retry_after(Duration::from_secs(5), Some(Duration::from_millis(100)));
        assert_eq!(merged, Duration::from_secs(5));
    }

    #[test]
    fn retry_after_clamped_to_max_delay() {
        let p = RetryPolicy::default();
        // Server says wait 10 minutes; we cap at 30s.
        let merged = p.merge_retry_after(Duration::from_millis(100), Some(Duration::from_secs(600)));
        assert_eq!(merged, Duration::from_secs(30));
    }

    #[test]
    fn parse_retry_after_handles_seconds() {
        assert_eq!(parse_retry_after("5"), Some(Duration::from_secs(5)));
        assert_eq!(parse_retry_after("  120  "), Some(Duration::from_secs(120)));
        assert_eq!(parse_retry_after("0"), Some(Duration::from_secs(0)));
    }

    #[test]
    fn parse_retry_after_rejects_garbage() {
        assert_eq!(parse_retry_after(""), None);
        assert_eq!(parse_retry_after("soon"), None);
        assert_eq!(parse_retry_after("-3"), None); // not a u64
        // HTTP-date form intentionally unsupported in this code path.
        assert_eq!(parse_retry_after("Wed, 21 Oct 2026 07:28:00 GMT"), None);
    }

    #[test]
    fn is_retryable_status_classifies_correctly() {
        // Retryable
        assert!(is_retryable_status(408));
        assert!(is_retryable_status(429));
        assert!(is_retryable_status(500));
        assert!(is_retryable_status(502));
        assert!(is_retryable_status(503));
        assert!(is_retryable_status(504));
        assert!(is_retryable_status(599));
        // NOT retryable (permanent client errors)
        assert!(!is_retryable_status(400));
        assert!(!is_retryable_status(401));
        assert!(!is_retryable_status(403));
        assert!(!is_retryable_status(404));
        assert!(!is_retryable_status(413));
        assert!(!is_retryable_status(422));
    }
}
