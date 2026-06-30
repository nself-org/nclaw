//! Async phase helpers for the benchmark runner.
//!
//! Extracted from `benchmark/mod.rs` to keep the runner entry-point under the
//! 300-line limit.  Both phases share the same `BenchmarkResult` / `GenOpts`
//! types from the parent module.

use super::{BenchmarkResult, CANONICAL_PROMPT, HARD_TIMEOUT, MEASUREMENT_TOKENS, WARMUP_TOKENS};
use crate::backend::{GenOpts, LlmBackend};
use crate::device::DeviceProbe;
use crate::error::CoreError;
use crate::tier::Tier;
use chrono::Utc;
use std::time::Duration;
use tokio::time::Instant;

// ---------------------------------------------------------------------------
// Outcome types
// ---------------------------------------------------------------------------

/// Outcome of the measurement phase.
pub(super) enum MeasurementOutcome {
    /// Measurement timed out — contains the early result to return.
    Timed(BenchmarkResult),
    /// Completed — (token_count, elapsed, timed_out_flag).
    Done(usize, std::time::Duration, bool),
}

pub(super) struct ComputedMetrics {
    pub(super) tokens_per_second: f64,
    pub(super) p99_latency_ms: u64,
    pub(super) ram_peak_mb: u64,
    pub(super) first_token_latency_ms: u64,
}

// ---------------------------------------------------------------------------
// Phase 1: warmup
// ---------------------------------------------------------------------------

/// Run the warmup phase (10 s budget, `WARMUP_TOKENS` tokens).
///
/// Returns `Ok(Some(result))` if the overall run should terminate early (hard
/// timeout after warmup); `Ok(None)` if warmup completed and measurement may
/// proceed; `Err(_)` on a hard LLM error.
pub(super) async fn run_warmup<B>(
    backend: &B,
    probe: &DeviceProbe,
    model_id: &str,
    tier: Tier,
    run_start: Instant,
) -> Result<Option<BenchmarkResult>, CoreError>
where
    B: LlmBackend + Send + Sync + ?Sized,
{
    let opts = GenOpts {
        model: model_id.to_string(),
        max_tokens: WARMUP_TOKENS as usize,
        temperature: 0.0,
        top_p: 1.0,
        stop_sequences: vec![],
    };
    let result = tokio::time::timeout(
        Duration::from_secs(10),
        backend.generate(CANONICAL_PROMPT, opts),
    )
    .await;
    // Non-fatal timeout; surface only hard LLM errors.
    if let Ok(Err(e)) = result {
        return Err(CoreError::Llm(e));
    }
    if run_start.elapsed() >= HARD_TIMEOUT {
        let r = make_timed_out_result(model_id, tier, probe);
        super::persist_result(&r)?;
        return Ok(Some(r));
    }
    Ok(None)
}

// ---------------------------------------------------------------------------
// Phase 2: measurement
// ---------------------------------------------------------------------------

/// Run the measurement phase (50 s budget, `MEASUREMENT_TOKENS` tokens).
pub(super) async fn run_measurement<B>(
    backend: &B,
    probe: &DeviceProbe,
    model_id: &str,
    tier: Tier,
    run_start: Instant,
) -> Result<MeasurementOutcome, CoreError>
where
    B: LlmBackend + Send + Sync + ?Sized,
{
    let opts = GenOpts {
        model: model_id.to_string(),
        max_tokens: MEASUREMENT_TOKENS as usize,
        temperature: 0.0,
        top_p: 1.0,
        stop_sequences: vec![],
    };
    let t0 = Instant::now();
    let result = tokio::time::timeout(
        Duration::from_secs(50),
        backend.generate(CANONICAL_PROMPT, opts),
    )
    .await;
    let elapsed = t0.elapsed();
    let timed_out = run_start.elapsed() >= HARD_TIMEOUT || result.is_err();

    match result {
        Ok(Ok(ts)) => Ok(MeasurementOutcome::Done(
            ts.tokens.len(),
            elapsed,
            timed_out,
        )),
        Ok(Err(e)) => Err(CoreError::Llm(e)),
        Err(_) => {
            let r = make_timed_out_result(model_id, tier, probe);
            super::persist_result(&r)?;
            Ok(MeasurementOutcome::Timed(r))
        }
    }
}

// ---------------------------------------------------------------------------
// Metric helpers
// ---------------------------------------------------------------------------

/// Build a timed-out `BenchmarkResult` with zeroed metrics.
pub(super) fn make_timed_out_result(
    model_id: &str,
    tier: Tier,
    probe: &DeviceProbe,
) -> BenchmarkResult {
    BenchmarkResult {
        timestamp: Utc::now(),
        model_id: model_id.to_string(),
        tier,
        tokens_per_second: 0.0,
        p99_latency_ms: 0,
        ram_peak_mb: probe.ram_total_mb.min(100),
        thermal_throttle_events: 0,
        first_token_latency_ms: 0,
        timed_out: true,
    }
}

/// Compute throughput + latency metrics from raw measurement data.
pub(super) fn compute_metrics(
    token_count: usize,
    elapsed: Duration,
    _timed_out: bool,
    probe: &DeviceProbe,
) -> ComputedMetrics {
    let elapsed_secs = elapsed.as_secs_f64();
    let tokens_per_second = if elapsed_secs > 0.0 && token_count > 0 {
        token_count as f64 / elapsed_secs
    } else {
        0.0
    };
    let per_token_ms: Vec<u64> = if token_count > 0 {
        let avg_ms = elapsed.as_millis() as u64 / token_count as u64;
        vec![avg_ms; token_count]
    } else {
        vec![0]
    };
    ComputedMetrics {
        tokens_per_second,
        p99_latency_ms: super::percentile_99(&per_token_ms),
        ram_peak_mb: probe.ram_total_mb.clamp(64, 100),
        first_token_latency_ms: per_token_ms.first().copied().unwrap_or(0),
    }
}
