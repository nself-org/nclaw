//! Public FFI surface for the Flutter mobile bridge.
//! flutter_rust_bridge_codegen reads this file to generate Dart bindings.
//! Exports only sync functions to avoid async complexity in the bridge.

use flutter_rust_bridge::frb;
use serde_json;

/// Return the nClaw library version (semver).
#[frb(sync)]
pub fn nclaw_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Probe the device and return its capabilities as JSON.
/// Used on app startup to determine tier eligibility and feature availability.
#[frb(sync)]
pub fn probe_device() -> String {
    let probe = crate::device::probe().unwrap_or_else(|_| crate::device::DeviceProbe::default());
    serde_json::to_string(&probe).unwrap_or_else(|_| "{}".to_string())
}

/// Classify the device tier based on probed capabilities and overrides.
/// Returns tier classification (T1, T2, T3, T4) as JSON.
/// `allow_t4` enables T4 classification on capable devices.
#[frb(sync)]
pub fn classify_tier(probe_json: String, allow_t4: bool) -> String {
    use crate::device::DeviceProbe;
    use crate::tier::{classify_tier as ct, TierOverride};

    let probe: DeviceProbe = serde_json::from_str(&probe_json).unwrap_or_default();
    let ovr = TierOverride {
        allow_t4,
        ..Default::default()
    };
    let tier = ct(&probe, &ovr);
    serde_json::to_string(&tier).unwrap_or_else(|_| "\"T2\"".to_string())
}
