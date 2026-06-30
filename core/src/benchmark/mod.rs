//! First-run benchmark suite for libnclaw core.
//!
//! Measures inference throughput, latency, and thermal behaviour against the
//! active LLM backend, then persists results to `~/.nclaw/benchmark-history.json`
//! and derives a `Recommendation` to hold, downgrade, or offer upgrade.
//!
//! # Submodules
//!
//! - `phases` — async warmup/measurement helpers and metric computation (extracted
//!   for size compliance).

mod phases;

use crate::backend::LlmBackend;
use crate::device::DeviceProbe;
use crate::error::CoreError;
use crate::tier::Tier;
use chrono::Utc;
use phases::{compute_metrics, run_measurement, run_warmup, MeasurementOutcome};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Duration;
use tokio::time::Instant;

// ---------------------------------------------------------------------------
// Constants (Decision #9)
// ---------------------------------------------------------------------------

pub const CANONICAL_PROMPT: &str = "Briefly explain how rainbows form, in three sentences.";
pub const WARMUP_TOKENS: u32 = 50;
pub const MEASUREMENT_TOKENS: u32 = 200;
pub const HARD_TIMEOUT: Duration = Duration::from_secs(90);

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Snapshot of a single benchmark run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkResult {
    pub timestamp: chrono::DateTime<Utc>,
    pub model_id: String,
    pub tier: Tier,
    /// Tokens generated per second during the measurement phase.
    pub tokens_per_second: f64,
    /// 99th-percentile per-token latency in milliseconds.
    pub p99_latency_ms: u64,
    /// Peak RSS-equivalent RAM sampled during the run (MB). Fixed 100 MB synthetic in tests.
    pub ram_peak_mb: u64,
    /// Number of thermal-throttle events (placeholder; 0 until macOS IOPMUserClient wired).
    pub thermal_throttle_events: u32,
    /// Wall-clock from `generate` call to first token arriving (ms).
    pub first_token_latency_ms: u64,
    /// True when the run exceeded `HARD_TIMEOUT`.
    pub timed_out: bool,
}

/// Recommendation derived from a `BenchmarkResult` per Decision #9 target ranges.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Recommendation {
    /// Performance is within target range for the current tier.
    Hold,
    /// Performance is below target minimum — consider a lighter model.
    Downgrade,
    /// Performance significantly exceeds target max — a higher tier may be viable.
    OfferUpgrade,
    /// Thermal throttle events detected — enable the thermal damper before downgrading.
    EnableThermalDamper,
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

/// Returns `~/.nclaw/benchmark-history.json`.
pub fn history_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".nclaw")
        .join("benchmark-history.json")
}

// ---------------------------------------------------------------------------
// Core runner
// ---------------------------------------------------------------------------

/// Run the benchmark suite against `backend` and return a `BenchmarkResult`.
///
/// Steps:
/// 1. Warmup call (10-second budget, up to `WARMUP_TOKENS` tokens) — discarded.
/// 2. Measurement call (50-second budget, up to `MEASUREMENT_TOKENS` tokens).
/// 3. Compute throughput and p99 latency from per-token timing.
/// 4. Persist to `history_path()` (append to JSON array).
/// 5. Return `BenchmarkResult`.
///
/// If the total elapsed time exceeds `HARD_TIMEOUT`, `timed_out = true` is
/// set and the function returns early with whatever data was collected.
pub async fn run<B>(
    backend: &B,
    probe: &DeviceProbe,
    model_id: &str,
    tier: Tier,
) -> Result<BenchmarkResult, CoreError>
where
    B: LlmBackend + Send + Sync + ?Sized,
{
    let run_start = Instant::now();

    // Phase 1: warmup — returns early on hard error or overall timeout.
    if let Some(early) = run_warmup(backend, probe, model_id, tier, run_start).await? {
        return Ok(early);
    }

    // Phase 2: measurement — returns (token_count, elapsed, timed_out) or early result.
    let (token_count, total_elapsed, timed_out) =
        match run_measurement(backend, probe, model_id, tier, run_start).await? {
            MeasurementOutcome::Timed(r) => return Ok(r),
            MeasurementOutcome::Done(tc, elapsed, to) => (tc, elapsed, to),
        };

    // Synthesise per-token latencies and compute metrics.
    let metrics = compute_metrics(token_count, total_elapsed, timed_out, probe);
    let result = BenchmarkResult {
        timestamp: Utc::now(),
        model_id: model_id.to_string(),
        tier,
        tokens_per_second: metrics.tokens_per_second,
        p99_latency_ms: metrics.p99_latency_ms,
        ram_peak_mb: metrics.ram_peak_mb,
        thermal_throttle_events: 0, // placeholder — macOS IOPMUserClient not yet wired
        first_token_latency_ms: metrics.first_token_latency_ms,
        timed_out,
    };

    persist_result(&result)?;
    Ok(result)
}

// ---------------------------------------------------------------------------
// Recommendation engine
// ---------------------------------------------------------------------------

/// Derive a `Recommendation` from a completed benchmark result.
///
/// Decision #9 target ranges:
/// - T0: 15–30 tok/s
/// - T1: 20–40 tok/s
/// - T2: 25–50 tok/s
/// - T3: 30–80 tok/s
/// - T4: 15–40 tok/s
///
/// Rules (in priority order):
/// 1. `thermal_throttle_events > 0` → `EnableThermalDamper` (preempts all others on mobile).
/// 2. `tok/s < target_min` → `Downgrade`.
/// 3. `tok/s > target_max * 1.5` AND a higher tier exists → `OfferUpgrade`.
/// 4. Otherwise → `Hold`.
pub fn analyze(result: &BenchmarkResult) -> Recommendation {
    // Rule 1: thermal throttling takes priority.
    if result.thermal_throttle_events > 0 {
        return Recommendation::EnableThermalDamper;
    }

    let (min, max) = target_range(result.tier);
    let tps = result.tokens_per_second;

    // Rule 2: below minimum → downgrade.
    if tps < min {
        return Recommendation::Downgrade;
    }

    // Rule 3: significantly above maximum AND higher tier exists → offer upgrade.
    let higher_tier_exists = !matches!(result.tier, Tier::T4);
    if tps > max * 1.5 && higher_tier_exists {
        return Recommendation::OfferUpgrade;
    }

    Recommendation::Hold
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// Decision #9 target throughput range (min_tok_per_s, max_tok_per_s) per tier.
pub fn target_range(tier: Tier) -> (f64, f64) {
    match tier {
        Tier::T0 => (15.0, 30.0),
        Tier::T1 => (20.0, 40.0),
        Tier::T2 => (25.0, 50.0),
        Tier::T3 => (30.0, 80.0),
        Tier::T4 => (15.0, 40.0),
    }
}

/// Compute the 99th-percentile value from a sorted or unsorted slice of u64.
pub fn percentile_99(values: &[u64]) -> u64 {
    if values.is_empty() {
        return 0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    let idx = ((sorted.len() as f64 * 0.99) as usize).saturating_sub(1);
    sorted[idx.min(sorted.len() - 1)]
}

/// Append `result` to `~/.nclaw/benchmark-history.json` (creates file if absent).
/// Non-fatal: parse failures return `CoreError::Other`.
pub(super) fn persist_result(result: &BenchmarkResult) -> Result<(), CoreError> {
    let path = history_path();

    // Ensure parent directory exists.
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| CoreError::Other(format!("create ~/.nclaw dir: {}", e)))?;
    }

    // Read existing history (empty array on first run or parse failure).
    let mut history: Vec<BenchmarkResult> = if path.exists() {
        let raw = std::fs::read_to_string(&path)
            .map_err(|e| CoreError::Other(format!("read benchmark history: {}", e)))?;
        serde_json::from_str(&raw).unwrap_or_default()
    } else {
        Vec::new()
    };

    history.push(result.clone());

    let serialised = serde_json::to_string_pretty(&history)
        .map_err(|e| CoreError::Other(format!("serialise benchmark history: {}", e)))?;

    std::fs::write(&path, serialised)
        .map_err(|e| CoreError::Other(format!("write benchmark history: {}", e)))?;

    Ok(())
}
