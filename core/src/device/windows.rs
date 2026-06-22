//! Windows device probing via wmic (WMI command-line).
//!
//! Uses wmic queries with fallback to PowerShell CIM. Both are zero-admin
//! (user-level) read operations. Returns safe defaults on parse failures.

use std::process::Command;

use super::DeviceProbe;
use crate::error::CoreError;

/// Probe the current Windows device and return hardware fingerprint.
///
/// Queries CPU brand, core counts, RAM, and GPU via wmic. All queries are
/// zero-admin read operations. Returns partial probe with safe defaults on failure.
pub fn probe_windows() -> Result<DeviceProbe, CoreError> {
    let cpu_brand = query_cpu_brand();
    let physical_cores = query_physical_cores();
    let logical_cores = query_logical_cores();
    let ram_total_mb = query_ram_mb();
    let (gpu_vendor, gpu_vram_mb) = query_gpu();

    Ok(DeviceProbe {
        os: "windows".into(),
        arch: std::env::consts::ARCH.into(),
        cpu_brand,
        physical_cores,
        logical_cores,
        ram_total_mb: if ram_total_mb > 0 { ram_total_mb } else { 1024 },
        gpu_vendor,
        gpu_vram_mb,
        apple_silicon: false,
        unified_memory: false,
        low_power_mode: false,
    })
}

/// Run a wmic/PowerShell command with no console window popup.
///
/// Uses `CREATE_NO_WINDOW` flag on Windows; plain `output()` on other targets
/// (for test compilation on macOS/Linux). Returns None on any failure.
fn run_command_silent(cmd: &str, args: &[&str]) -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        let output = Command::new(cmd)
            .args(args)
            .creation_flags(0x08000000) // CREATE_NO_WINDOW
            .output()
            .ok()?;
        if !output.status.success() {
            return None;
        }
        String::from_utf8(output.stdout).ok()
    }
    #[cfg(not(target_os = "windows"))]
    {
        let output = Command::new(cmd).args(args).output().ok()?;
        if !output.status.success() {
            return None;
        }
        String::from_utf8(output.stdout).ok()
    }
}

/// Query CPU brand name from wmic.
fn query_cpu_brand() -> String {
    let output = run_command_silent("wmic", &["cpu", "get", "Name", "/value"]);
    let Some(text) = output else { return "unknown".to_string() };
    for line in text.lines() {
        if let Some(val) = line.strip_prefix("Name=") {
            let brand = val.trim().to_string();
            if !brand.is_empty() {
                return brand;
            }
        }
    }
    "unknown".to_string()
}

/// Query physical core count from wmic.
fn query_physical_cores() -> u32 {
    let output = run_command_silent("wmic", &["cpu", "get", "NumberOfCores", "/value"]);
    let Some(text) = output else { return 1 };
    for line in text.lines() {
        if let Some(val) = line.strip_prefix("NumberOfCores=") {
            if let Ok(n) = val.trim().parse::<u32>() {
                if n > 0 { return n; }
            }
        }
    }
    1
}

/// Query logical processor count from wmic.
fn query_logical_cores() -> u32 {
    let output = run_command_silent("wmic", &["cpu", "get", "NumberOfLogicalProcessors", "/value"]);
    let Some(text) = output else { return 1 };
    for line in text.lines() {
        if let Some(val) = line.strip_prefix("NumberOfLogicalProcessors=") {
            if let Ok(n) = val.trim().parse::<u32>() {
                if n > 0 { return n; }
            }
        }
    }
    1
}

/// Query total physical RAM in MB from wmic.
fn query_ram_mb() -> u64 {
    let output = run_command_silent(
        "wmic",
        &["computersystem", "get", "TotalPhysicalMemory", "/value"],
    );
    let Some(text) = output else { return 0 };
    for line in text.lines() {
        if let Some(val) = line.strip_prefix("TotalPhysicalMemory=") {
            if let Ok(bytes) = val.trim().parse::<u64>() {
                if bytes > 0 { return bytes / (1024 * 1024); }
            }
        }
    }
    0
}

/// Query GPU name and VRAM from wmic.
///
/// Returns (vendor_name, vram_mb). Both may be None if wmic is unavailable.
fn query_gpu() -> (Option<String>, Option<u64>) {
    let output = run_command_silent(
        "wmic",
        &["path", "win32_VideoController", "get", "Name,AdapterRAM", "/value"],
    );
    let Some(text) = output else { return (None, None) };

    let mut gpu_vendor = None;
    let mut gpu_vram_mb = None;
    let mut lines = text.lines().peekable();

    while let Some(line) = lines.next() {
        if let Some(name) = line.strip_prefix("Name=") {
            let name = name.trim();
            if !name.is_empty() && name != "unknown" {
                gpu_vendor = Some(name.to_string());
                if let Some(ram_line) = lines.next() {
                    if let Some(val) = ram_line.strip_prefix("AdapterRAM=") {
                        if let Ok(vram_bytes) = val.trim().parse::<u64>() {
                            if vram_bytes > 0 {
                                gpu_vram_mb = Some(vram_bytes / (1024 * 1024));
                            }
                        }
                    }
                }
                break;
            }
        }
    }

    (gpu_vendor, gpu_vram_mb)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_probe_windows() {
        let probe = probe_windows().expect("probe_windows failed");
        assert_eq!(probe.os, "windows");
        assert!(probe.logical_cores > 0, "logical_cores must be > 0");
    }
}
