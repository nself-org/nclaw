//! Device probing and hardware fingerprinting for tier classification.
//!
//! Collects OS, CPU, memory, GPU, and power-state telemetry from the current device.
//! Used by tier classifier to select appropriate model tier and cache strategy.

use serde::{Deserialize, Serialize};
use std::process::Command;
use std::sync::atomic::AtomicBool;

use crate::error::{CoreError, LlmError};

/// Hardware fingerprint of the current device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceProbe {
    /// OS identifier: "macos", "linux", "windows", "ios", "android"
    pub os: String,
    /// CPU architecture: "aarch64", "x86_64"
    pub arch: String,
    /// CPU brand string (e.g., "Apple M3 Pro")
    pub cpu_brand: String,
    /// Physical CPU core count
    pub physical_cores: u32,
    /// Logical CPU core count (including hyperthreads)
    pub logical_cores: u32,
    /// Total system RAM in MB
    pub ram_total_mb: u64,
    /// GPU vendor (optional, e.g., "Apple", "NVIDIA")
    pub gpu_vendor: Option<String>,
    /// GPU VRAM in MB (optional)
    pub gpu_vram_mb: Option<u64>,
    /// True if running on Apple Silicon (ARM64)
    pub apple_silicon: bool,
    /// True if Apple Silicon with unified memory architecture
    pub unified_memory: bool,
    /// True if device is in low-power mode (iOS, macOS 12+)
    pub low_power_mode: bool,
}

impl Default for DeviceProbe {
    fn default() -> Self {
        Self {
            os: "unknown".into(),
            arch: "unknown".into(),
            cpu_brand: "unknown".into(),
            physical_cores: 0,
            logical_cores: 0,
            ram_total_mb: 0,
            gpu_vendor: None,
            gpu_vram_mb: None,
            apple_silicon: false,
            unified_memory: false,
            low_power_mode: false,
        }
    }
}

/// Probe the current macOS device and return hardware fingerprint.
///
/// Runs zero-admin sysctl commands only. No sudo, no osascript.
/// Returns CoreError::Llm if any required sysctl fails.
#[cfg(target_os = "macos")]
pub fn probe_macos() -> Result<DeviceProbe, CoreError> {
    let cpu_brand = run_sysctl("machdep.cpu.brand_string")?;
    let physical_cores_str = run_sysctl("hw.physicalcpu")?;
    let logical_cores_str = run_sysctl("hw.logicalcpu")?;
    let memsize_str = run_sysctl("hw.memsize")?;
    let arm64_str = run_sysctl("hw.optional.arm64")?;

    let physical_cores = physical_cores_str.trim().parse::<u32>().map_err(|e| {
        CoreError::Llm(LlmError::InternalError(format!(
            "parse physical cores: {}",
            e
        )))
    })?;

    let logical_cores = logical_cores_str.trim().parse::<u32>().map_err(|e| {
        CoreError::Llm(LlmError::InternalError(format!(
            "parse logical cores: {}",
            e
        )))
    })?;

    let memsize_bytes = memsize_str
        .trim()
        .parse::<u64>()
        .map_err(|e| CoreError::Llm(LlmError::InternalError(format!("parse memsize: {}", e))))?;

    let ram_total_mb = memsize_bytes / (1024 * 1024);

    let apple_silicon = arm64_str.trim() == "1";

    Ok(DeviceProbe {
        os: "macos".into(),
        arch: if apple_silicon { "aarch64" } else { "x86_64" }.into(),
        cpu_brand,
        physical_cores,
        logical_cores,
        ram_total_mb,
        gpu_vendor: None,
        gpu_vram_mb: None,
        apple_silicon,
        unified_memory: apple_silicon,
        low_power_mode: false,
    })
}

/// Run `sysctl -n <key>` and return trimmed output.
#[cfg(target_os = "macos")]
fn run_sysctl(key: &str) -> Result<String, CoreError> {
    let output = Command::new("sysctl")
        .args(&["-n", key])
        .output()
        .map_err(|e| {
            CoreError::Llm(LlmError::InternalError(format!(
                "sysctl {} failed: {}",
                key, e
            )))
        })?;

    if !output.status.success() {
        return Err(CoreError::Llm(LlmError::InternalError(format!(
            "sysctl {} returned non-zero",
            key
        ))));
    }

    String::from_utf8(output.stdout).map_err(|e| {
        CoreError::Llm(LlmError::InternalError(format!(
            "sysctl {} utf8 error: {}",
            key, e
        )))
    })
}

/// Probe the current Linux device and return hardware fingerprint.
///
/// Reads /proc/cpuinfo, /proc/meminfo, and optionally runs lspci.
/// No sudo, no root required. Returns partial DeviceProbe with safe defaults on parse failures.
#[cfg(target_os = "linux")]
pub fn probe_linux() -> Result<DeviceProbe, CoreError> {
    use std::collections::HashSet;
    use std::fs;

    let mut cpu_brand = "unknown".to_string();
    let mut logical_cores = 0u32;
    let mut physical_cores_set = HashSet::new();
    let mut current_physical_id = String::new();
    let mut ram_total_mb = 0u64;
    let mut gpu_vendor = None;

    // Parse /proc/cpuinfo for CPU and core counts
    if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
        for line in cpuinfo.lines() {
            if line.starts_with("model name") && cpu_brand == "unknown" {
                if let Some(val) = line.split(':').nth(1) {
                    cpu_brand = val.trim().to_string();
                }
            }
            if line.starts_with("processor") {
                logical_cores += 1;
            }
            if line.starts_with("physical id") {
                if let Some(val) = line.split(':').nth(1) {
                    current_physical_id = val.trim().to_string();
                }
            }
            if line.starts_with("core id") {
                if let Some(val) = line.split(':').nth(1) {
                    let core_id = val.trim().to_string();
                    if !current_physical_id.is_empty() {
                        physical_cores_set.insert(format!("{}:{}", current_physical_id, core_id));
                    }
                }
            }
        }
    }

    // Fallback physical cores count if core parsing failed
    let physical_cores = if !physical_cores_set.is_empty() {
        physical_cores_set.len() as u32
    } else if logical_cores > 0 {
        (logical_cores + 1) / 2 // conservative estimate: logical / 2
    } else {
        1
    };

    // Parse /proc/meminfo for RAM
    if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines() {
            if line.starts_with("MemTotal") {
                if let Some(val) = line.split_whitespace().nth(1) {
                    if let Ok(kb) = val.parse::<u64>() {
                        ram_total_mb = kb / 1024;
                    }
                }
                break;
            }
        }
    }

    // Attempt lspci for GPU detection (non-fatal if missing or parse fails)
    if let Ok(output) = Command::new("lspci").args(&["-mm"]).output() {
        if output.status.success() {
            if let Ok(lspci_out) = String::from_utf8(output.stdout) {
                for line in lspci_out.lines() {
                    if line.contains("VGA") || line.contains("3D controller") {
                        if line.contains("NVIDIA") {
                            gpu_vendor = Some("NVIDIA".to_string());
                            break;
                        } else if line.contains("AMD") {
                            gpu_vendor = Some("AMD".to_string());
                            break;
                        } else if line.contains("Intel") {
                            gpu_vendor = Some("Intel".to_string());
                            break;
                        }
                    }
                }
            }
        }
    }

    Ok(DeviceProbe {
        os: "linux".into(),
        arch: std::env::consts::ARCH.into(),
        cpu_brand,
        physical_cores: if physical_cores > 0 {
            physical_cores
        } else {
            1
        },
        logical_cores: if logical_cores > 0 { logical_cores } else { 1 },
        ram_total_mb: if ram_total_mb > 0 { ram_total_mb } else { 1024 }, // safe fallback
        gpu_vendor,
        gpu_vram_mb: None,
        apple_silicon: false,
        unified_memory: false,
        low_power_mode: false,
    })
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    #[test]
    fn test_probe_macos() {
        let probe = probe_macos().expect("probe_macos failed");
        assert_eq!(probe.os, "macos");
        assert!(probe.physical_cores > 0, "physical_cores must be > 0");
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
        assert!(probe.ram_total_mb > 0, "ram_total_mb must be > 0");
        assert!(!probe.cpu_brand.is_empty(), "cpu_brand must not be empty");
    }

    #[test]
    fn test_device_probe_default() {
        let probe = DeviceProbe::default();
        assert_eq!(probe.os, "unknown");
        assert_eq!(probe.arch, "unknown");
        assert_eq!(probe.physical_cores, 0);
    }
}

/// Probe the current Windows device and return hardware fingerprint.
///
/// Uses WMI queries (wmic command) with fallback to PowerShell CIM.
/// Both are zero-admin (user-level) read operations.
/// Returns safe defaults on parse failures — never panics.
#[cfg(target_os = "windows")]
pub fn probe_windows() -> Result<DeviceProbe, CoreError> {
    use std::process::Command;

    #[cfg(target_os = "windows")]
    use std::os::windows::process::CommandExt;

    // Helper: run a command with no console window popup (CREATE_NO_WINDOW = 0x08000000)
    #[cfg(target_os = "windows")]
    fn run_command_silent(cmd: &str, args: &[&str]) -> Option<String> {
        let output = Command::new(cmd)
            .args(args)
            .creation_flags(0x08000000)
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        String::from_utf8(output.stdout).ok()
    }

    #[cfg(not(target_os = "windows"))]
    fn run_command_silent(cmd: &str, args: &[&str]) -> Option<String> {
        let output = Command::new(cmd).args(args).output().ok()?;

        if !output.status.success() {
            return None;
        }

        String::from_utf8(output.stdout).ok()
    }

    let mut cpu_brand = "unknown".to_string();
    let mut physical_cores = 1u32;
    let mut logical_cores = 1u32;
    let mut ram_total_mb = 0u64;
    let mut gpu_vendor = None;
    let mut gpu_vram_mb = None;

    // CPU brand from wmic
    if let Some(output) = run_command_silent("wmic", &["cpu", "get", "Name", "/value"]) {
        for line in output.lines() {
            if line.starts_with("Name=") {
                cpu_brand = line
                    .strip_prefix("Name=")
                    .unwrap_or("unknown")
                    .trim()
                    .to_string();
                if cpu_brand.is_empty() {
                    cpu_brand = "unknown".to_string();
                }
                break;
            }
        }
    }

    // Physical cores from wmic
    if let Some(output) = run_command_silent("wmic", &["cpu", "get", "NumberOfCores", "/value"]) {
        for line in output.lines() {
            if line.starts_with("NumberOfCores=") {
                if let Ok(n) = line
                    .strip_prefix("NumberOfCores=")
                    .unwrap_or("0")
                    .trim()
                    .parse::<u32>()
                {
                    if n > 0 {
                        physical_cores = n;
                    }
                }
                break;
            }
        }
    }

    // Logical cores from wmic
    if let Some(output) = run_command_silent(
        "wmic",
        &["cpu", "get", "NumberOfLogicalProcessors", "/value"],
    ) {
        for line in output.lines() {
            if line.starts_with("NumberOfLogicalProcessors=") {
                if let Ok(n) = line
                    .strip_prefix("NumberOfLogicalProcessors=")
                    .unwrap_or("0")
                    .trim()
                    .parse::<u32>()
                {
                    if n > 0 {
                        logical_cores = n;
                    }
                }
                break;
            }
        }
    }

    // RAM from wmic (in bytes)
    if let Some(output) = run_command_silent(
        "wmic",
        &["computersystem", "get", "TotalPhysicalMemory", "/value"],
    ) {
        for line in output.lines() {
            if line.starts_with("TotalPhysicalMemory=") {
                if let Ok(bytes) = line
                    .strip_prefix("TotalPhysicalMemory=")
                    .unwrap_or("0")
                    .trim()
                    .parse::<u64>()
                {
                    if bytes > 0 {
                        ram_total_mb = bytes / (1024 * 1024);
                    }
                }
                break;
            }
        }
    }

    // GPU from wmic
    if let Some(output) = run_command_silent(
        "wmic",
        &[
            "path",
            "win32_VideoController",
            "get",
            "Name,AdapterRAM",
            "/value",
        ],
    ) {
        let mut lines = output.lines();
        while let Some(line) = lines.next() {
            if line.starts_with("Name=") {
                let name = line.strip_prefix("Name=").unwrap_or("").trim();
                if !name.is_empty() && name != "unknown" {
                    gpu_vendor = Some(name.to_string());
                    // Next line may have AdapterRAM
                    if let Some(ram_line) = lines.next() {
                        if ram_line.starts_with("AdapterRAM=") {
                            if let Ok(vram_bytes) = ram_line
                                .strip_prefix("AdapterRAM=")
                                .unwrap_or("0")
                                .trim()
                                .parse::<u64>()
                            {
                                if vram_bytes > 0 {
                                    gpu_vram_mb = Some(vram_bytes / (1024 * 1024));
                                }
                            }
                        }
                    }
                }
                break;
            }
        }
    }

    Ok(DeviceProbe {
        os: "windows".into(),
        arch: std::env::consts::ARCH.into(),
        cpu_brand,
        physical_cores,
        logical_cores,
        ram_total_mb: if ram_total_mb > 0 { ram_total_mb } else { 1024 }, // safe fallback
        gpu_vendor,
        gpu_vram_mb,
        apple_silicon: false,
        unified_memory: false,
        low_power_mode: false,
    })
}

#[cfg(all(test, target_os = "linux"))]
mod tests_linux {
    use super::*;

    #[test]
    fn test_probe_linux() {
        let probe = probe_linux().expect("probe_linux failed");
        assert_eq!(probe.os, "linux");
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
        assert!(probe.ram_total_mb > 0, "ram_total_mb must be > 0");
    }
}

#[cfg(all(test, target_os = "windows"))]
mod tests_windows {
    use super::*;

    #[test]
    fn test_probe_windows() {
        let probe = probe_windows().expect("probe_windows failed");
        assert_eq!(probe.os, "windows");
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
    }
}

/// Low-power mode flag set by Flutter via FFI (iOS).
/// Default: false. Use `ios_set_low_power(true)` from Flutter layer.
static IOS_LOW_POWER_MODE: AtomicBool = AtomicBool::new(false);

/// Set the low-power mode flag (callable from Flutter FFI).
/// iOS does not expose `UIDevice.isLowPowerModeEnabled` via C API, so the Flutter
/// layer must check at runtime and call this to persist the flag in the Rust core.
#[cfg(target_os = "ios")]
pub fn ios_set_low_power(flag: bool) {
    IOS_LOW_POWER_MODE.store(flag, Ordering::Relaxed);
}

/// Probe the current iOS device and return hardware fingerprint.
///
/// Uses sysctl syscalls (available on iOS) to read device model, CPU counts, and RAM.
/// No admin privilege required. GPU VRAM is None (no public API). Low-power mode is
/// set via `ios_set_low_power()` from the Flutter layer.
///
/// Returns CoreError::Llm if any required sysctl fails.
#[cfg(target_os = "ios")]
pub fn probe_ios() -> Result<DeviceProbe, CoreError> {
    use std::ffi::CStr;

    // Helper: call sysctlbyname and return trimmed String
    fn sysctl_string(key: &str) -> Result<String, CoreError> {
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

    // Helper: call sysctlbyname and parse as u32
    fn sysctl_u32(key: &str) -> Result<u32, CoreError> {
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

    // Helper: call sysctlbyname and parse as u64
    fn sysctl_u64(key: &str) -> Result<u64, CoreError> {
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

    // Read device model (e.g., "iPhone14,5")
    let cpu_brand = sysctl_string("hw.machine")?;

    // Read physical cores
    let physical_cores = sysctl_u32("hw.physicalcpu")?;

    // Read logical cores
    let logical_cores = sysctl_u32("hw.logicalcpu")?;

    // Read total RAM in bytes
    let memsize_bytes = sysctl_u64("hw.memsize")?;
    let ram_total_mb = memsize_bytes / (1024 * 1024);

    // Check if ARM64 (always true on modern iOS)
    let arm64 = sysctl_u32("hw.optional.arm64").unwrap_or(1) == 1;

    // Read low-power mode flag (set via ios_set_low_power)
    let low_power_mode = IOS_LOW_POWER_MODE.load(Ordering::Relaxed);

    Ok(DeviceProbe {
        os: "ios".into(),
        arch: if arm64 { "aarch64" } else { "x86_64" }.into(),
        cpu_brand,
        physical_cores,
        logical_cores,
        ram_total_mb,
        gpu_vendor: Some("Apple".into()), // iOS always has Apple GPU
        gpu_vram_mb: None,                // No public API to query unified memory size
        apple_silicon: arm64,             // Assume ARM64 = Apple Silicon
        unified_memory: true,             // iOS always uses unified memory architecture
        low_power_mode,
    })
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

/// Probe the current Android device and return hardware fingerprint.
///
/// Reads /proc/cpuinfo for CPU + core info, /proc/meminfo for RAM.
/// No admin required. Returns safe defaults on parse failures.
/// Battery and low-power-mode state are injected from Android FFI.
#[cfg(target_os = "android")]
pub fn probe_android() -> Result<DeviceProbe, CoreError> {
    use std::fs;

    let mut cpu_brand = "unknown".to_string();
    let mut logical_cores = 0u32;
    let mut ram_total_mb = 0u64;

    // Parse /proc/cpuinfo for CPU brand (Hardware field on Android) and core count
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

    // Parse /proc/meminfo for RAM (MemTotal in kB)
    if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines() {
            if line.starts_with("MemTotal") {
                if let Some(val) = line.split_whitespace().nth(1) {
                    if let Ok(kb) = val.parse::<u64>() {
                        ram_total_mb = kb / 1024;
                    }
                }
                break;
            }
        }
    }

    // Ensure sensible defaults if parsing failed
    if logical_cores == 0 {
        logical_cores = 1;
    }
    if ram_total_mb == 0 {
        ram_total_mb = 1024; // conservative fallback
    }

    Ok(DeviceProbe {
        os: "android".into(),
        arch: std::env::consts::ARCH.into(),
        cpu_brand: if cpu_brand == "unknown" {
            "Android".to_string()
        } else {
            cpu_brand
        },
        physical_cores: logical_cores, // Android doesn't expose distinct cores cleanly
        logical_cores,
        ram_total_mb,
        gpu_vendor: None, // most Android devices have integrated GPU; vram unreliable
        gpu_vram_mb: None,
        apple_silicon: false,
        unified_memory: true, // most Android devices share RAM with GPU
        low_power_mode: ANDROID_LOW_POWER.load(Ordering::Relaxed),
    })
}

// Static storage for Android battery and low-power-mode state (set from Kotlin FFI)
#[cfg(target_os = "android")]
static ANDROID_BATTERY_PERCENT: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(100);

#[cfg(target_os = "android")]
static ANDROID_LOW_POWER: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Set Android device battery percentage (called from Kotlin FFI).
#[cfg(target_os = "android")]
pub fn android_set_battery_percent(pct: u8) {
    ANDROID_BATTERY_PERCENT.store(pct, Ordering::Relaxed);
}

/// Set Android device low-power-mode flag (called from Kotlin FFI).
#[cfg(target_os = "android")]
pub fn android_set_low_power(flag: bool) {
    ANDROID_LOW_POWER.store(flag, Ordering::Relaxed);
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

/// Auto-dispatch probe() to the correct platform function.
pub fn probe() -> Result<DeviceProbe, CoreError> {
    #[cfg(target_os = "macos")]
    {
        return probe_macos();
    }
    #[cfg(target_os = "linux")]
    {
        return probe_linux();
    }
    #[cfg(target_os = "windows")]
    {
        return probe_windows();
    }
    #[cfg(target_os = "ios")]
    {
        return probe_ios();
    }
    #[cfg(target_os = "android")]
    {
        return probe_android();
    }
    #[cfg(not(any(
        target_os = "macos",
        target_os = "linux",
        target_os = "windows",
        target_os = "ios",
        target_os = "android"
    )))]
    {
        return Err(CoreError::Llm(LlmError::InternalError(
            "unsupported platform".into(),
        )));
    }
}
