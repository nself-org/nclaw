//! Power and thermal dampers for mobile inference.
//!
//! Pure-function module — no I/O, no async, no global state reads. All
//! platform state is passed in via [`DamperState`] so these functions are
//! fully unit-testable in isolation.
//!
//! Three dampers are defined:
//!
//! 1. **Low-power damper** — drops the inferred [`Tier`] by one level when
//!    Low Power Mode is active, reducing model size and context window.
//!
//! 2. **Battery damper** — disables local LLM execution entirely when the
//!    battery is below a threshold and the device is not charging.
//!
//! 3. **Thermal damper** — injects an inter-token delay during streaming to
//!    reduce sustained CPU/GPU load under thermal pressure.
//!
//! Integration points:
//! - Tier classifier calls [`apply_low_power_damper`] after classifying hardware.
//! - Benchmark/model-loader calls [`local_llm_disabled_by_battery`] before
//!   loading a local model.
//! - The streaming layer calls [`thermal_inter_token_delay_ms`] between each
//!   generated token.

use crate::tier::Tier;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Snapshot of mobile power/thermal state passed to each damper function.
///
/// Callers construct this from the global atomics in [`crate::mobile_ffi`]
/// or from test fixtures. No mutable references; all functions are pure.
#[derive(Debug, Clone)]
pub struct DamperState {
    /// Whether Low Power Mode is currently active (iOS/Android).
    pub low_power: bool,
    /// Current battery percentage (0–100).
    pub battery_pct: u8,
    /// Whether the device is currently charging.
    pub charging: bool,
    /// Current thermal pressure level.
    pub thermal_level: ThermalLevel,
    /// Battery percentage below which local LLM is suspended (default 30).
    pub battery_threshold_pct: u8,
}

impl Default for DamperState {
    fn default() -> Self {
        Self {
            low_power: false,
            battery_pct: 100,
            charging: true,
            thermal_level: ThermalLevel::Nominal,
            battery_threshold_pct: 30,
        }
    }
}

/// Thermal pressure levels mirroring iOS `ProcessInfo.ThermalState` and
/// Android `PowerManager` thermal status constants.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThermalLevel {
    /// No thermal pressure. Full inference speed.
    Nominal,
    /// Mild warmth — within normal operating range. No throttle applied.
    Fair,
    /// Device is meaningfully hot. A 50 ms inter-token delay is injected.
    Serious,
    /// Device is critically hot. A 200 ms inter-token delay is injected.
    Critical,
}

impl ThermalLevel {
    /// Convert from the raw u8 written by [`crate::mobile_ffi::nclaw_set_thermal_level`].
    /// Values above 3 are clamped to [`ThermalLevel::Critical`].
    pub fn from_u8(v: u8) -> Self {
        match v {
            0 => ThermalLevel::Nominal,
            1 => ThermalLevel::Fair,
            2 => ThermalLevel::Serious,
            _ => ThermalLevel::Critical,
        }
    }
}

// ---------------------------------------------------------------------------
// Damper 1 — Low-power tier reduction
// ---------------------------------------------------------------------------

/// Apply the low-power damper: when `low_power` is true, drop `tier` by one
/// level (T0 stays T0 — it is the minimum tier).
///
/// This is a pure function; callers supply the current Low Power flag rather
/// than reading global state directly, which keeps tests simple.
///
/// # Examples
///
/// ```
/// use libnclaw::llm::dampers::apply_low_power_damper;
/// use libnclaw::tier::Tier;
///
/// assert_eq!(apply_low_power_damper(Tier::T2, true),  Tier::T1);
/// assert_eq!(apply_low_power_damper(Tier::T2, false), Tier::T2);
/// assert_eq!(apply_low_power_damper(Tier::T0, true),  Tier::T0); // floor
/// ```
pub fn apply_low_power_damper(tier: Tier, low_power: bool) -> Tier {
    if !low_power {
        return tier;
    }
    match tier {
        Tier::T0 => Tier::T0,
        Tier::T1 => Tier::T0,
        Tier::T2 => Tier::T1,
        Tier::T3 => Tier::T2,
        Tier::T4 => Tier::T3,
    }
}

// ---------------------------------------------------------------------------
// Damper 2 — Battery-based local-LLM disable
// ---------------------------------------------------------------------------

/// Returns `true` when local LLM inference should be suspended due to low
/// battery. Inference is suspended when:
///   - The device is **not** charging, **and**
///   - `battery_pct` is **below** `battery_threshold_pct` (default 30 %).
///
/// When charging, inference always proceeds regardless of battery level.
///
/// # Examples
///
/// ```
/// use libnclaw::llm::dampers::{DamperState, local_llm_disabled_by_battery};
///
/// let mut s = DamperState::default();
/// s.battery_pct = 20;
/// s.charging = false;
/// assert!(local_llm_disabled_by_battery(&s));
///
/// s.charging = true;
/// assert!(!local_llm_disabled_by_battery(&s)); // charging — allow
///
/// s.charging = false;
/// s.battery_pct = 50;
/// assert!(!local_llm_disabled_by_battery(&s)); // above threshold — allow
/// ```
pub fn local_llm_disabled_by_battery(state: &DamperState) -> bool {
    !state.charging && state.battery_pct < state.battery_threshold_pct
}

// ---------------------------------------------------------------------------
// Damper 3 — Thermal inter-token delay
// ---------------------------------------------------------------------------

/// Returns the number of milliseconds to sleep between generated tokens at
/// the given thermal level.
///
/// | Level    | Delay |
/// |----------|-------|
/// | Nominal  |  0 ms |
/// | Fair     |  0 ms |
/// | Serious  | 50 ms |
/// | Critical |200 ms |
///
/// The streaming layer inserts `tokio::time::sleep(Duration::from_millis(n))`
/// after each token when `n > 0`.
///
/// # Examples
///
/// ```
/// use libnclaw::llm::dampers::{ThermalLevel, thermal_inter_token_delay_ms};
///
/// assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Nominal),  0);
/// assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Fair),     0);
/// assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Serious),  50);
/// assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Critical), 200);
/// ```
pub fn thermal_inter_token_delay_ms(level: ThermalLevel) -> u64 {
    match level {
        ThermalLevel::Nominal | ThermalLevel::Fair => 0,
        ThermalLevel::Serious => 50,
        ThermalLevel::Critical => 200,
    }
}

// ---------------------------------------------------------------------------
// Unit tests — ≥6 covering all three dampers
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // --- Low-power damper ---

    #[test]
    fn low_power_off_leaves_tier_unchanged() {
        assert_eq!(apply_low_power_damper(Tier::T3, false), Tier::T3);
        assert_eq!(apply_low_power_damper(Tier::T0, false), Tier::T0);
        assert_eq!(apply_low_power_damper(Tier::T4, false), Tier::T4);
    }

    #[test]
    fn low_power_on_drops_one_tier() {
        assert_eq!(apply_low_power_damper(Tier::T1, true), Tier::T0);
        assert_eq!(apply_low_power_damper(Tier::T2, true), Tier::T1);
        assert_eq!(apply_low_power_damper(Tier::T3, true), Tier::T2);
        assert_eq!(apply_low_power_damper(Tier::T4, true), Tier::T3);
    }

    #[test]
    fn low_power_on_t0_stays_t0() {
        // T0 is the floor — cannot drop below it.
        assert_eq!(apply_low_power_damper(Tier::T0, true), Tier::T0);
    }

    // --- Battery damper ---

    #[test]
    fn battery_below_threshold_not_charging_disables_llm() {
        let state = DamperState {
            battery_pct: 15,
            charging: false,
            battery_threshold_pct: 30,
            ..Default::default()
        };
        assert!(local_llm_disabled_by_battery(&state));
    }

    #[test]
    fn battery_below_threshold_but_charging_allows_llm() {
        let state = DamperState {
            battery_pct: 10,
            charging: true,
            battery_threshold_pct: 30,
            ..Default::default()
        };
        assert!(!local_llm_disabled_by_battery(&state));
    }

    #[test]
    fn battery_above_threshold_not_charging_allows_llm() {
        let state = DamperState {
            battery_pct: 80,
            charging: false,
            battery_threshold_pct: 30,
            ..Default::default()
        };
        assert!(!local_llm_disabled_by_battery(&state));
    }

    #[test]
    fn battery_exactly_at_threshold_not_charging_allows_llm() {
        // Threshold is strictly less-than, so equality is NOT disabled.
        let state = DamperState {
            battery_pct: 30,
            charging: false,
            battery_threshold_pct: 30,
            ..Default::default()
        };
        assert!(!local_llm_disabled_by_battery(&state));
    }

    // --- Thermal damper ---

    #[test]
    fn thermal_nominal_and_fair_have_zero_delay() {
        assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Nominal), 0);
        assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Fair), 0);
    }

    #[test]
    fn thermal_serious_has_50ms_delay() {
        assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Serious), 50);
    }

    #[test]
    fn thermal_critical_has_200ms_delay() {
        assert_eq!(thermal_inter_token_delay_ms(ThermalLevel::Critical), 200);
    }

    #[test]
    fn thermal_level_from_u8_clamps_above_3() {
        assert_eq!(ThermalLevel::from_u8(0), ThermalLevel::Nominal);
        assert_eq!(ThermalLevel::from_u8(1), ThermalLevel::Fair);
        assert_eq!(ThermalLevel::from_u8(2), ThermalLevel::Serious);
        assert_eq!(ThermalLevel::from_u8(3), ThermalLevel::Critical);
        assert_eq!(ThermalLevel::from_u8(99), ThermalLevel::Critical);
    }
}
