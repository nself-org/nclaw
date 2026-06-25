//! macOS device probing via sysctl.
//!
//! Collects CPU brand, core counts, RAM, and Apple Silicon flag from sysctl.
//! No sudo or admin privileges required.

use std::process::Command;

use crate::error::{CoreError, LlmError};

use super::DeviceProbe;

/// Probe the current macOS device and return hardware fingerprint.
///
/// Runs zero-admin sysctl commands only. No sudo, no osascript.
/// Returns CoreError::Llm if any required sysctl fails.
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
///
/// # Errors
/// Returns `CoreError::Llm` if the sysctl command fails to spawn, exits non-zero,
/// or produces non-UTF-8 output.
fn run_sysctl(key: &str) -> Result<String, CoreError> {
    let output = Command::new("sysctl")
        .args(["-n", key])
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

#[cfg(test)]
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
