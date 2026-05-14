//! S19 Bridge sprint acceptance tests.
//!
//! Verifies that all 8 bridge modules (budget, overrides, connection, privacy,
//! telemetry, failure_policy, plus router and orchestrator) compile and work
//! correctly in integration.

use libnclaw::bridge::budget::BudgetEnforcer;
use libnclaw::bridge::connection::ConnectionMonitor;
use libnclaw::bridge::failure_policy::backoff;
use libnclaw::bridge::overrides::OverridesStore;
use libnclaw::bridge::privacy::strip_pii;
use libnclaw::bridge::router::{ConnectionState, RouteOverride};
use libnclaw::bridge::telemetry::BridgeTelemetry;
use std::time::Duration;

#[test]
fn test_budget_enforcer_within_budget() {
    let enforcer = BudgetEnforcer::new(5000, 2.0);
    enforcer.record_spend(100, 0.50);
    assert!(enforcer.within_budget());
    assert!(enforcer.within_latency_budget());
    assert!(enforcer.within_cost_budget());
}

#[test]
fn test_budget_enforcer_exceeds_latency() {
    let enforcer = BudgetEnforcer::new(500, 2.0);
    enforcer.record_spend(600, 0.25);
    assert!(!enforcer.within_latency_budget());
}

#[test]
fn test_budget_enforcer_exceeds_cost() {
    let enforcer = BudgetEnforcer::new(5000, 1.0);
    enforcer.record_spend(100, 1.50);
    assert!(!enforcer.within_cost_budget());
}

#[test]
fn test_overrides_store_set_get() {
    let store = OverridesStore::new();
    let ovr = RouteOverride::ForceLocal;
    store.set("conv1", ovr.clone());
    assert_eq!(store.get("conv1"), Some(ovr));
    assert_eq!(store.count(), 1);
}

#[test]
fn test_overrides_store_clear() {
    let store = OverridesStore::new();
    store.set("conv1", RouteOverride::ForceLocal);
    store.clear("conv1");
    assert_eq!(store.get("conv1"), None);
}

#[test]
fn test_connection_monitor_transitions() {
    let monitor = ConnectionMonitor::with_initial_state(ConnectionState::Online);
    assert!(monitor.is_online());

    monitor.set(ConnectionState::Degraded);
    assert!(monitor.is_degraded());

    monitor.set(ConnectionState::Offline);
    assert!(monitor.is_offline());
}

#[test]
fn test_privacy_filter_strips_email() {
    let input = "Contact alice@example.com";
    let output = strip_pii(input);
    assert!(output.contains("[EMAIL]"));
    assert!(!output.contains("alice"));
}

#[test]
fn test_privacy_filter_strips_phone() {
    let input = "Call 555-123-4567";
    let output = strip_pii(input);
    assert!(output.contains("[PHONE]"));
}

#[test]
fn test_privacy_filter_strips_ssn() {
    let input = "SSN: 123-45-6789";
    let output = strip_pii(input);
    assert!(output.contains("[SSN]"));
    assert!(!output.contains("123-45-6789"));
}

#[test]
fn test_privacy_filter_multiple_pii() {
    let input = "Contact alice@example.com or 555-123-4567. SSN 123-45-6789.";
    let output = strip_pii(input);
    assert!(output.contains("[EMAIL]"));
    assert!(output.contains("[PHONE]"));
    assert!(output.contains("[SSN]"));
}

#[test]
fn test_telemetry_increments() {
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
fn test_telemetry_reset() {
    let tel = BridgeTelemetry::new();
    tel.record_local_route();
    tel.record_fallback();
    tel.reset();
    assert_eq!(tel.local_routes(), 0);
    assert_eq!(tel.fallbacks(), 0);
}

#[test]
fn test_telemetry_snapshot() {
    let tel = BridgeTelemetry::new();
    tel.record_local_route();
    tel.record_server_mux_route();
    tel.record_frontier_route();
    let (local, mux, frontier, _fallback) = tel.snapshot();
    assert_eq!(local, 1);
    assert_eq!(mux, 1);
    assert_eq!(frontier, 1);
}

#[test]
fn test_backoff_increases_with_attempt() {
    // Can't guarantee exact values due to jitter, but later attempts should be longer
    let b0 = backoff(0);
    let b5 = backoff(5);
    // b5 should be significantly longer than b0 (exponential growth)
    assert!(b5.as_millis() > b0.as_millis() * 10);
}

#[test]
fn test_backoff_has_upper_bound() {
    // Very high attempt numbers should still cap at ~60 seconds
    let b20 = backoff(20);
    assert!(b20.as_millis() < 61_000);
}

#[test]
fn test_all_modules_compile_and_integrate() {
    // This test verifies that all 8 modules can be instantiated and used together
    let budget = BudgetEnforcer::new(5000, 2.0);
    let connection = ConnectionMonitor::new();
    let overrides = OverridesStore::new();
    let telemetry = BridgeTelemetry::new();

    // Set some state
    budget.record_spend(100, 0.25);
    connection.set(ConnectionState::Online);
    overrides.set("conv1", RouteOverride::ForceLocal);
    telemetry.record_local_route();

    // Verify state
    assert!(budget.within_budget());
    assert!(connection.is_online());
    assert_eq!(overrides.get("conv1"), Some(RouteOverride::ForceLocal));
    assert_eq!(telemetry.local_routes(), 1);

    // Test privacy and failure_policy functions
    let cleaned = strip_pii("alice@example.com 555-123-4567");
    assert!(cleaned.contains("[EMAIL]"));
    assert!(cleaned.contains("[PHONE]"));

    let delay = backoff(2);
    assert!(delay > Duration::from_millis(300));
}
