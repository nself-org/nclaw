//! Linux device probing via /proc filesystem and lspci.
//!
//! Reads /proc/cpuinfo, /proc/meminfo, and optionally runs lspci.
//! No sudo or root required. Returns partial DeviceProbe with safe defaults on parse failures.

use std::collections::HashSet;
use std::fs;
use std::process::Command;

use super::DeviceProbe;
use crate::error::CoreError;

/// Probe the current Linux device and return hardware fingerprint.
///
/// Reads /proc/cpuinfo for CPU brand and core counts, /proc/meminfo for RAM,
/// and optionally runs lspci for GPU detection. All zero-privilege.
/// Returns safe defaults when /proc entries are unavailable.
pub fn probe_linux() -> Result<DeviceProbe, CoreError> {
    let (cpu_brand, logical_cores, physical_cores) = parse_cpuinfo();
    let ram_total_mb = parse_meminfo();
    let gpu_vendor = detect_gpu_vendor();

    Ok(DeviceProbe {
        os: "linux".into(),
        arch: std::env::consts::ARCH.into(),
        cpu_brand,
        physical_cores: if physical_cores > 0 { physical_cores } else { 1 },
        logical_cores: if logical_cores > 0 { logical_cores } else { 1 },
        ram_total_mb: if ram_total_mb > 0 { ram_total_mb } else { 1024 },
        gpu_vendor,
        gpu_vram_mb: None,
        apple_silicon: false,
        unified_memory: false,
        low_power_mode: false,
    })
}

/// Parse /proc/cpuinfo for CPU brand, logical core count, and physical core estimate.
///
/// Returns (cpu_brand, logical_cores, physical_cores). Falls back to safe defaults
/// on missing or unparseable entries.
fn parse_cpuinfo() -> (String, u32, u32) {
    let mut cpu_brand = "unknown".to_string();
    let mut logical_cores = 0u32;
    let mut physical_cores_set = HashSet::new();
    let mut current_physical_id = String::new();

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

    let physical_cores = if !physical_cores_set.is_empty() {
        physical_cores_set.len() as u32
    } else if logical_cores > 0 {
        logical_cores.div_ceil(2) // conservative estimate: logical / 2
    } else {
        1
    };

    (cpu_brand, logical_cores, physical_cores)
}

/// Parse /proc/meminfo for total RAM in MB.
///
/// Returns 0 if the file is unavailable or the MemTotal entry cannot be parsed.
fn parse_meminfo() -> u64 {
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
    0
}

/// Detect GPU vendor via lspci (non-fatal; returns None if lspci is unavailable).
///
/// Recognises NVIDIA, AMD, and Intel GPU entries in the VGA/3D controller class.
fn detect_gpu_vendor() -> Option<String> {
    let output = Command::new("lspci").args(["-mm"]).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let lspci_out = String::from_utf8(output.stdout).ok()?;
    for line in lspci_out.lines() {
        if line.contains("VGA") || line.contains("3D controller") {
            if line.contains("NVIDIA") {
                return Some("NVIDIA".to_string());
            } else if line.contains("AMD") {
                return Some("AMD".to_string());
            } else if line.contains("Intel") {
                return Some("Intel".to_string());
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_probe_linux() {
        let probe = probe_linux().expect("probe_linux failed");
        assert_eq!(probe.os, "linux");
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
        assert!(probe.ram_total_mb > 0, "ram_total_mb must be > 0");
    }
}
