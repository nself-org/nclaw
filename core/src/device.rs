//! Device probing and hardware fingerprinting for tier classification.
//!
//! Collects OS, CPU, memory, GPU, and power-state telemetry from the current device.
//! Used by tier classifier to select appropriate model tier and cache strategy.

use serde::{Deserialize, Serialize};
use std::process::Command;

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

    let physical_cores = physical_cores_str
        .trim()
        .parse::<u32>()
        .map_err(|e| CoreError::Llm(LlmError::InternalError(format!("parse physical cores: {}", e))))?;

    let logical_cores = logical_cores_str
        .trim()
        .parse::<u32>()
        .map_err(|e| CoreError::Llm(LlmError::InternalError(format!("parse logical cores: {}", e))))?;

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
            CoreError::Llm(LlmError::InternalError(format!("sysctl {} failed: {}", key, e)))
        })?;

    if !output.status.success() {
        return Err(CoreError::Llm(LlmError::InternalError(format!(
            "sysctl {} returned non-zero",
            key
        ))));
    }

    String::from_utf8(output.stdout)
        .map_err(|e| CoreError::Llm(LlmError::InternalError(format!("sysctl {} utf8 error: {}", key, e))))
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
