//! Integration tests for libnclaw::benchmark — recommendation engine and utility fns.

use libnclaw::benchmark::{
    analyze, history_path, percentile_99, target_range, BenchmarkResult, Recommendation,
};
use libnclaw::tier::Tier;

#[test]
fn target_ranges_are_correct() {
    assert_eq!(target_range(Tier::T0), (15.0, 30.0));
    assert_eq!(target_range(Tier::T1), (20.0, 40.0));
    assert_eq!(target_range(Tier::T2), (25.0, 50.0));
    assert_eq!(target_range(Tier::T3), (30.0, 80.0));
    assert_eq!(target_range(Tier::T4), (15.0, 40.0));
}

#[test]
fn percentile_99_single_element() {
    assert_eq!(percentile_99(&[42]), 42);
}

#[test]
fn percentile_99_empty() {
    assert_eq!(percentile_99(&[]), 0);
}

#[test]
fn percentile_99_100_elements() {
    let values: Vec<u64> = (1..=100).collect();
    assert_eq!(percentile_99(&values), 99);
}

fn make_result(tier: Tier, tps: f64, thermal: u32) -> BenchmarkResult {
    BenchmarkResult {
        timestamp: chrono::Utc::now(),
        model_id: "test".into(),
        tier,
        tokens_per_second: tps,
        p99_latency_ms: 30,
        ram_peak_mb: 100,
        thermal_throttle_events: thermal,
        first_token_latency_ms: 20,
        timed_out: false,
    }
}

#[test]
fn analyze_hold_within_range() {
    assert_eq!(
        analyze(&make_result(Tier::T2, 35.0, 0)),
        Recommendation::Hold
    );
}

#[test]
fn analyze_downgrade_below_min() {
    assert_eq!(
        analyze(&make_result(Tier::T2, 5.0, 0)),
        Recommendation::Downgrade
    );
}

#[test]
fn analyze_offer_upgrade_above_max_1_5x() {
    assert_eq!(
        analyze(&make_result(Tier::T0, 100.0, 0)),
        Recommendation::OfferUpgrade
    );
}

#[test]
fn analyze_thermal_damper_preempts() {
    assert_eq!(
        analyze(&make_result(Tier::T2, 5.0, 2)),
        Recommendation::EnableThermalDamper
    );
}

#[test]
fn analyze_t4_no_upgrade_offered() {
    assert_eq!(
        analyze(&make_result(Tier::T4, 200.0, 0)),
        Recommendation::Hold
    );
}

#[test]
fn history_path_contains_nclaw() {
    let path = history_path();
    let path_str = path.to_string_lossy();
    assert!(
        path_str.contains(".nclaw"),
        "expected .nclaw in path, got: {}",
        path_str
    );
    assert!(path_str.ends_with("benchmark-history.json"));
}
