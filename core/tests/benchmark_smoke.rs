//! Smoke tests for the nclaw-core benchmark suite (Decision #9).
//!
//! Uses a `TimedLlm` test double that emits a controlled number of tokens with
//! a configurable per-token delay, giving deterministic throughput assertions.

use libnclaw::backend::{GenOpts, LlmBackend, TokenStream};
use libnclaw::benchmark::{self, Recommendation, CANONICAL_PROMPT};
use libnclaw::device::DeviceProbe;
use libnclaw::error::LlmError;
use libnclaw::tier::Tier;
use std::time::Duration;

// ---------------------------------------------------------------------------
// Test double: TimedLlm
// ---------------------------------------------------------------------------

/// Mock LLM that emits `token_count` tokens with `delay_per_token` sleep between
/// each token. Simulates streaming by sleeping the total delay before returning.
struct TimedLlm {
    token_count: usize,
    delay_per_token: Duration,
}

#[async_trait::async_trait]
impl LlmBackend for TimedLlm {
    async fn generate(&self, _prompt: &str, opts: GenOpts) -> Result<TokenStream, LlmError> {
        let count = self.token_count.min(opts.max_tokens);
        let total_delay = self.delay_per_token * count as u32;
        tokio::time::sleep(total_delay).await;
        Ok(TokenStream {
            tokens: vec!["tok".to_string(); count],
            finish_reason: "stop".into(),
        })
    }

    async fn embed(&self, _text: &str) -> Result<Vec<f32>, LlmError> {
        Ok(vec![])
    }

    fn supports_streaming(&self) -> bool {
        false
    }

    fn provider(&self) -> &str {
        "timed-mock"
    }
}

// ---------------------------------------------------------------------------
// Synthetic DeviceProbe helper
// ---------------------------------------------------------------------------

fn synthetic_probe() -> DeviceProbe {
    DeviceProbe {
        os: "macos".into(),
        arch: "aarch64".into(),
        cpu_brand: "M1".into(),
        physical_cores: 8,
        logical_cores: 8,
        ram_total_mb: 16384,
        gpu_vendor: None,
        gpu_vram_mb: None,
        apple_silicon: true,
        unified_memory: true,
        low_power_mode: false,
    }
}

// ---------------------------------------------------------------------------
// Test 1: ~100 tok/s synthetic backend, tier T2 → Hold
// ---------------------------------------------------------------------------

/// 250 tokens at 10ms each = 2.5 seconds total.
/// tokens_per_second ≈ 250 / 2.5 = 100 tok/s.
/// Tier T2 target range: 25–50 tok/s → 100 is above max*1.5 (75) → OfferUpgrade.
///
/// NOTE: This validates the recommendation logic rather than a strict 100 tok/s
/// assertion, because async test timing on CI may vary. We assert:
/// - timed_out == false
/// - tokens_per_second > 25 (above T2 minimum)
/// - Recommendation is OfferUpgrade (100 >> 50*1.5=75)
#[tokio::test]
async fn test_benchmark_100_tps_tier_t2_offer_upgrade() {
    let backend = TimedLlm {
        token_count: 250,
        delay_per_token: Duration::from_millis(10),
    };
    let probe = synthetic_probe();

    let result = benchmark::run(&backend, &probe, "mock-model-t2", Tier::T2)
        .await
        .expect("benchmark run failed");

    assert!(!result.timed_out, "should not time out");
    assert!(
        result.tokens_per_second > 25.0,
        "expected >25 tok/s, got {}",
        result.tokens_per_second
    );
    assert_eq!(result.model_id, "mock-model-t2");
    assert_eq!(result.tier, Tier::T2);
    assert_eq!(result.thermal_throttle_events, 0);

    let rec = benchmark::analyze(&result);
    assert_eq!(
        rec,
        Recommendation::OfferUpgrade,
        "100 tok/s >> T2 max*1.5 (75) should be OfferUpgrade, got {:?}",
        rec
    );
}

// ---------------------------------------------------------------------------
// Test 2: 5 tok/s synthetic, tier T2 → Downgrade
// ---------------------------------------------------------------------------

/// 10 tokens at 200ms each = 2.0 seconds.
/// tokens_per_second ≈ 10 / 2.0 = 5 tok/s.
/// Tier T2 minimum: 25 tok/s → 5 < 25 → Downgrade.
#[tokio::test]
async fn test_benchmark_slow_tps_tier_t2_downgrade() {
    let backend = TimedLlm {
        token_count: 10,
        delay_per_token: Duration::from_millis(200),
    };
    let probe = synthetic_probe();

    let result = benchmark::run(&backend, &probe, "mock-model-slow", Tier::T2)
        .await
        .expect("benchmark run failed");

    assert!(!result.timed_out, "should not time out");
    assert!(
        result.tokens_per_second < 25.0,
        "expected <25 tok/s, got {}",
        result.tokens_per_second
    );

    let rec = benchmark::analyze(&result);
    assert_eq!(
        rec,
        Recommendation::Downgrade,
        "5 tok/s < T2 min (25) should be Downgrade, got {:?}",
        rec
    );
}

// ---------------------------------------------------------------------------
// Test 3: 100 tok/s synthetic, tier T0 → OfferUpgrade
// ---------------------------------------------------------------------------

/// Same high-throughput backend as Test 1, but tier T0 (target: 15–30 tok/s).
/// 100 tok/s >> 30 * 1.5 = 45 → OfferUpgrade.
#[tokio::test]
async fn test_benchmark_100_tps_tier_t0_offer_upgrade() {
    let backend = TimedLlm {
        token_count: 250,
        delay_per_token: Duration::from_millis(10),
    };
    let probe = synthetic_probe();

    let result = benchmark::run(&backend, &probe, "mock-model-t0", Tier::T0)
        .await
        .expect("benchmark run failed");

    assert!(!result.timed_out, "should not time out");

    let rec = benchmark::analyze(&result);
    assert_eq!(
        rec,
        Recommendation::OfferUpgrade,
        "100 tok/s >> T0 max*1.5 (45) should be OfferUpgrade, got {:?}",
        rec
    );
}

// ---------------------------------------------------------------------------
// Test 4: Thermal throttle preempts other recommendations
// ---------------------------------------------------------------------------

/// Directly tests `analyze()` with a throttled result — no backend call needed.
#[test]
fn test_analyze_thermal_throttle_preempts_downgrade() {
    let result = libnclaw::benchmark::BenchmarkResult {
        timestamp: chrono::Utc::now(),
        model_id: "mock".into(),
        tier: Tier::T2,
        tokens_per_second: 5.0, // would be Downgrade without thermal events
        p99_latency_ms: 200,
        ram_peak_mb: 100,
        thermal_throttle_events: 1,
        first_token_latency_ms: 100,
        timed_out: false,
    };
    assert_eq!(
        benchmark::analyze(&result),
        Recommendation::EnableThermalDamper
    );
}

// ---------------------------------------------------------------------------
// Test 5: history_path sanity
// ---------------------------------------------------------------------------

#[test]
fn test_history_path_contains_nclaw_suffix() {
    let path = benchmark::history_path();
    let s = path.to_string_lossy();
    assert!(s.contains(".nclaw"), "path should contain .nclaw: {}", s);
    assert!(
        s.ends_with("benchmark-history.json"),
        "path should end with benchmark-history.json: {}",
        s
    );
}

// ---------------------------------------------------------------------------
// Test 6: CANONICAL_PROMPT is non-empty
// ---------------------------------------------------------------------------

#[test]
fn test_canonical_prompt_is_non_empty() {
    assert!(!CANONICAL_PROMPT.is_empty());
}
