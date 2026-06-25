//! Device probing and hardware fingerprinting for tier classification.
//!
//! Collects OS, CPU, memory, GPU, and power-state telemetry from the current device.
//! Used by tier classifier to select appropriate model tier and cache strategy.
//!
//! Platform-specific probe implementations live in submodules:
//! - `macos`: macOS sysctl probing
//! - `linux`: /proc/cpuinfo + /proc/meminfo + lspci probing
//! - `windows`: WMI/wmic probing
//! - `mobile`: iOS sysctl + Android /proc probing, FFI setters

use serde::{Deserialize, Serialize};

use crate::error::CoreError;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "windows")]
mod windows;
#[cfg(any(target_os = "ios", target_os = "android"))]
mod mobile;

#[cfg(target_os = "macos")]
pub use macos::probe_macos;
#[cfg(target_os = "linux")]
pub use linux::probe_linux;
#[cfg(target_os = "windows")]
pub use windows::probe_windows;
#[cfg(target_os = "ios")]
pub use mobile::{ios_set_low_power, probe_ios};
#[cfg(target_os = "android")]
pub use mobile::{android_set_battery_percent, android_set_low_power, probe_android};

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

/// Auto-dispatch probe() to the correct platform function.
pub fn probe() -> Result<DeviceProbe, CoreError> {
    // Exactly one cfg block compiles per target, so each is the function's tail
    // expression — no `return` needed (and clippy::needless_return forbids it).
    #[cfg(target_os = "macos")]
    {
        macos::probe_macos()
    }
    #[cfg(target_os = "linux")]
    {
        linux::probe_linux()
    }
    #[cfg(target_os = "windows")]
    {
        windows::probe_windows()
    }
    #[cfg(target_os = "ios")]
    {
        mobile::probe_ios()
    }
    #[cfg(target_os = "android")]
    {
        mobile::probe_android()
    }
    #[cfg(not(any(
        target_os = "macos",
        target_os = "linux",
        target_os = "windows",
        target_os = "ios",
        target_os = "android"
    )))]
    {
        Err(CoreError::Llm(crate::error::LlmError::InternalError(
            "unsupported platform".into(),
        )))
    }
}
