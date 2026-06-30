//! Mobile device probing: iOS (sysctl) and Android (/proc filesystem).
//!
//! iOS: uses sysctlbyname for CPU model, core counts, and RAM. Low-power mode
//!   is injected from the Flutter layer via `ios_set_low_power()`.
//!
//! Android: reads /proc/cpuinfo and /proc/meminfo. Battery percent and low-power
//!   mode are injected from Kotlin FFI via `android_set_battery_percent()` and
//!   `android_set_low_power()`.
//!
//! GPU VRAM is unavailable on both platforms via public APIs.

use super::DeviceProbe;
use crate::error::{CoreError, LlmError};

// ── iOS ──────────────────────────────────────────────────────────────────────

/// Global low-power mode flag for iOS, set by `ios_set_low_power()` from Flutter.
///
/// iOS does not expose `UIDevice.isLowPowerModeEnabled` via C API; the Flutter
/// layer checks at runtime and persists the flag here.
#[cfg(target_os = "ios")]
static IOS_LOW_POWER_MODE: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// Set the iOS low-power mode flag (callable from Flutter FFI).
///
/// # Arguments
/// * `flag` – `true` if the device is in Low Power Mode.
#[cfg(target_os = "ios")]
pub fn ios_set_low_power(flag: bool) {
    IOS_LOW_POWER_MODE.store(flag, std::sync::atomic::Ordering::Relaxed);
}

/// Probe the current iOS device and return a hardware fingerprint.
///
/// Uses `sysctlbyname` to read device model, CPU counts, and RAM. No admin
/// privilege required. GPU VRAM is not available via public API; `gpu_vram_mb`
/// is always `None`. Low-power mode must be set in advance via `ios_set_low_power()`.
///
/// # Errors
/// Returns `CoreError::Llm` if any required sysctl call fails.
#[cfg(target_os = "ios")]
pub fn probe_ios() -> Result<DeviceProbe, CoreError> {
    let cpu_brand = ios_sysctl_string("hw.machine")?;
    let physical_cores = ios_sysctl_u32("hw.physicalcpu")?;
    let logical_cores = ios_sysctl_u32("hw.logicalcpu")?;
    let memsize_bytes = ios_sysctl_u64("hw.memsize")?;
    let ram_total_mb = memsize_bytes / (1024 * 1024);
    let arm64 = ios_sysctl_u32("hw.optional.arm64").unwrap_or(1) == 1;
    let low_power_mode = IOS_LOW_POWER_MODE.load(std::sync::atomic::Ordering::Relaxed);

    Ok(DeviceProbe {
        os: "ios".into(),
        arch: if arm64 { "aarch64" } else { "x86_64" }.into(),
        cpu_brand,
        physical_cores,
        logical_cores,
        ram_total_mb,
        gpu_vendor: Some("Apple".into()),
        gpu_vram_mb: None,
        apple_silicon: arm64,
        unified_memory: true,
        low_power_mode,
    })
}

/// Call `sysctlbyname` and return the result as a UTF-8 string (iOS only).
#[cfg(target_os = "ios")]
fn ios_sysctl_string(key: &str) -> Result<String, CoreError> {
    let c_key = std::ffi::CString::new(key).map_err(|e| {
        CoreError::Llm(LlmError::InternalError(format!(
            "CString conversion for sysctl key: {}",
            e
        )))
    })?;
    let mut value = vec![0u8; 256];
    let mut len = value.len();
    let result = unsafe {
        libc::sysctlbyname(
            c_key.as_ptr(),
            value.as_mut_ptr() as *mut libc::c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if result != 0 {
        return Err(CoreError::Llm(LlmError::InternalError(format!(
            "sysctl {} failed: {}",
            key,
            std::io::Error::last_os_error()
        ))));
    }
    value.truncate(len);
    String::from_utf8(value)
        .map(|s| s.trim_end_matches('\0').to_string())
        .map_err(|e| {
            CoreError::Llm(LlmError::InternalError(format!(
                "sysctl {} utf8 error: {}",
                key, e
            )))
        })
}

/// Call `sysctlbyname` and parse result as `u32` (iOS only).
#[cfg(target_os = "ios")]
fn ios_sysctl_u32(key: &str) -> Result<u32, CoreError> {
    let c_key = std::ffi::CString::new(key).map_err(|e| {
        CoreError::Llm(LlmError::InternalError(format!(
            "CString conversion for sysctl key: {}",
            e
        )))
    })?;
    let mut value: u32 = 0;
    let mut len = std::mem::size_of::<u32>();
    let result = unsafe {
        libc::sysctlbyname(
            c_key.as_ptr(),
            &mut value as *mut u32 as *mut libc::c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if result != 0 {
        return Err(CoreError::Llm(LlmError::InternalError(format!(
            "sysctl {} failed: {}",
            key,
            std::io::Error::last_os_error()
        ))));
    }
    Ok(value)
}

/// Call `sysctlbyname` and parse result as `u64` (iOS only).
#[cfg(target_os = "ios")]
fn ios_sysctl_u64(key: &str) -> Result<u64, CoreError> {
    let c_key = std::ffi::CString::new(key).map_err(|e| {
        CoreError::Llm(LlmError::InternalError(format!(
            "CString conversion for sysctl key: {}",
            e
        )))
    })?;
    let mut value: u64 = 0;
    let mut len = std::mem::size_of::<u64>();
    let result = unsafe {
        libc::sysctlbyname(
            c_key.as_ptr(),
            &mut value as *mut u64 as *mut libc::c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if result != 0 {
        return Err(CoreError::Llm(LlmError::InternalError(format!(
            "sysctl {} failed: {}",
            key,
            std::io::Error::last_os_error()
        ))));
    }
    Ok(value)
}

#[cfg(all(test, target_os = "ios"))]
mod tests_ios {
    use super::*;

    #[test]
    fn test_probe_ios() {
        let probe = probe_ios().expect("probe_ios failed");
        assert_eq!(probe.os, "ios");
        assert!(probe.apple_silicon, "iOS must be Apple Silicon");
        assert!(probe.unified_memory, "iOS must have unified memory");
        assert_eq!(probe.gpu_vendor, Some("Apple".to_string()));
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
        assert!(probe.ram_total_mb > 0, "ram_total_mb must be > 0");
    }

    #[test]
    fn test_ios_set_low_power() {
        ios_set_low_power(true);
        let probe = probe_ios().expect("probe_ios failed");
        assert!(probe.low_power_mode, "low_power_mode must be true");

        ios_set_low_power(false);
        let probe = probe_ios().expect("probe_ios failed");
        assert!(!probe.low_power_mode, "low_power_mode must be false");
    }
}

// ── Android ──────────────────────────────────────────────────────────────────

/// Battery percentage for Android, injected from Kotlin FFI.
#[cfg(target_os = "android")]
static ANDROID_BATTERY_PERCENT: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(100);

/// Low-power mode flag for Android, injected from Kotlin FFI.
#[cfg(target_os = "android")]
static ANDROID_LOW_POWER: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Set Android device battery percentage (called from Kotlin FFI).
///
/// # Arguments
/// * `pct` – Battery percentage 0–100.
#[cfg(target_os = "android")]
pub fn android_set_battery_percent(pct: u8) {
    ANDROID_BATTERY_PERCENT.store(pct, std::sync::atomic::Ordering::Relaxed);
}

/// Set Android device low-power-mode flag (called from Kotlin FFI).
///
/// # Arguments
/// * `flag` – `true` if the device is in battery saver / low-power mode.
#[cfg(target_os = "android")]
pub fn android_set_low_power(flag: bool) {
    ANDROID_LOW_POWER.store(flag, std::sync::atomic::Ordering::Relaxed);
}

/// Probe the current Android device and return a hardware fingerprint.
///
/// Reads /proc/cpuinfo for CPU brand and core counts, /proc/meminfo for RAM.
/// Battery and low-power state are injected from Kotlin FFI. No admin required.
/// Returns safe defaults when /proc entries cannot be parsed.
///
/// # Errors
/// Always returns `Ok` — falls back to safe defaults rather than erroring.
#[cfg(target_os = "android")]
pub fn probe_android() -> Result<DeviceProbe, CoreError> {
    use std::fs;
    use std::sync::atomic::Ordering;

    let (cpu_brand, logical_cores) = parse_android_cpuinfo();
    let ram_total_mb = parse_android_meminfo();
    let low_power_mode = ANDROID_LOW_POWER.load(Ordering::Relaxed);

    Ok(DeviceProbe {
        os: "android".into(),
        arch: std::env::consts::ARCH.into(),
        cpu_brand,
        physical_cores: logical_cores,
        logical_cores,
        ram_total_mb,
        gpu_vendor: None,
        gpu_vram_mb: None,
        apple_silicon: false,
        unified_memory: true,
        low_power_mode,
    })
}

/// Parse /proc/cpuinfo for CPU brand and logical core count on Android.
#[cfg(target_os = "android")]
fn parse_android_cpuinfo() -> (String, u32) {
    use std::fs;

    let mut cpu_brand = "unknown".to_string();
    let mut logical_cores = 0u32;

    if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
        for line in cpuinfo.lines() {
            if line.starts_with("Hardware") && cpu_brand == "unknown" {
                if let Some(val) = line.split(':').nth(1) {
                    cpu_brand = val.trim().to_string();
                }
            }
            if line.starts_with("processor") {
                logical_cores += 1;
            }
        }
    }

    if cpu_brand == "unknown" {
        cpu_brand = "Android".to_string();
    }
    if logical_cores == 0 {
        logical_cores = 1;
    }

    (cpu_brand, logical_cores)
}

/// Parse /proc/meminfo for total RAM in MB on Android.
#[cfg(target_os = "android")]
fn parse_android_meminfo() -> u64 {
    use std::fs;

    if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines() {
            if line.starts_with("MemTotal") {
                if let Some(val) = line.split_whitespace().nth(1) {
                    if let Ok(kb) = val.parse::<u64>() {
                        return kb / 1024;
                    }
                }
                break;
            }
        }
    }
    1024 // conservative fallback
}

#[cfg(all(test, target_os = "android"))]
mod tests_android {
    use super::*;

    #[test]
    fn test_probe_android() {
        let probe = probe_android().expect("probe_android failed");
        assert_eq!(probe.os, "android");
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
        assert!(probe.ram_total_mb > 0, "ram_total_mb must be > 0");
    }

    #[test]
    fn test_android_low_power_setter() {
        android_set_low_power(true);
        let probe = probe_android().expect("probe_android failed");
        assert!(probe.low_power_mode, "low_power_mode must be set");

        android_set_low_power(false);
        let probe = probe_android().expect("probe_android failed");
        assert!(!probe.low_power_mode, "low_power_mode must be unset");
    }
}
