//! Mobile FFI damper exports — C-ABI functions callable from Swift (iOS) and
//! Kotlin/JNI (Android).
//!
//! These three functions are the only runtime-mutable entry points the platform
//! layer uses to notify Rust of power and thermal state changes. All state is
//! stored in atomics so the calls are lock-free and safe to invoke from any
//! platform thread.
//!
//! The values are read by [`crate::llm::dampers`] during tier classification
//! and inference streaming.
//!
//! Compiled only on iOS and Android targets (cfg guard below). On desktop the
//! platform provides richer power APIs directly; mobile uses the C ABI because
//! Swift and Kotlin cannot call Rust async code without this bridge.

use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};

// ---------------------------------------------------------------------------
// Global atomic state — written from Swift/Kotlin, read from Rust inference
// ---------------------------------------------------------------------------

/// Whether iOS/Android Low Power Mode is currently active.
pub(crate) static LOW_POWER_MODE: AtomicBool = AtomicBool::new(false);

/// Current battery percentage (0–100). 255 = unknown.
pub(crate) static BATTERY_PCT: AtomicU8 = AtomicU8::new(100);

/// Thermal pressure level: 0=nominal, 1=fair, 2=serious, 3=critical.
pub(crate) static THERMAL_LEVEL: AtomicU8 = AtomicU8::new(0);

// ---------------------------------------------------------------------------
// Public readers (used by dampers.rs)
// ---------------------------------------------------------------------------

/// Returns true when Low Power Mode is active.
#[inline]
pub fn is_low_power() -> bool {
    LOW_POWER_MODE.load(Ordering::Relaxed)
}

/// Returns the current battery percentage (0–100). 100 when unknown.
#[inline]
pub fn battery_pct() -> u8 {
    BATTERY_PCT.load(Ordering::Relaxed)
}

/// Returns the current thermal level (0–3).
#[inline]
pub fn thermal_level() -> u8 {
    THERMAL_LEVEL.load(Ordering::Relaxed)
}

// ---------------------------------------------------------------------------
// C-ABI exports — #[no_mangle] so the linker can find them by name
// ---------------------------------------------------------------------------

/// Notify libnclaw that iOS/Android Low Power Mode is on or off.
///
/// When `flag` is `true` the tier classifier drops one tier to reduce
/// inference load. Platform callers should invoke this:
/// - iOS: on `NSProcessInfoPowerStateDidChange` notification
/// - Android: on `ACTION_POWER_SAVE_MODE_CHANGED` broadcast
#[no_mangle]
pub extern "C" fn nclaw_set_low_power(flag: bool) {
    LOW_POWER_MODE.store(flag, Ordering::Relaxed);
}

/// Notify libnclaw of the current battery percentage (0–100).
///
/// Values above 100 are clamped to 100. When below the configured threshold
/// (default 30 %) and not charging, local LLM inference is suspended.
/// Platform callers should invoke this on `BatteryManager` / `UIDevice`
/// battery level change events.
#[no_mangle]
pub extern "C" fn nclaw_set_battery_pct(pct: u8) {
    BATTERY_PCT.store(pct.min(100), Ordering::Relaxed);
}

/// Notify libnclaw of the current thermal pressure level (0–3).
///
/// | Level | Meaning  | Inference effect                  |
/// |-------|----------|-----------------------------------|
/// | 0     | Nominal  | No throttle                       |
/// | 1     | Fair     | No throttle                       |
/// | 2     | Serious  | 50 ms inter-token delay            |
/// | 3     | Critical | 200 ms inter-token delay           |
///
/// Values above 3 are clamped to 3. Platform callers should invoke this on
/// `ProcessInfo.thermalState` change (iOS) or `PowerManager` thermal status
/// callbacks (Android API 29+).
#[no_mangle]
pub extern "C" fn nclaw_set_thermal_level(level: u8) {
    THERMAL_LEVEL.store(level.min(3), Ordering::Relaxed);
}
