//! VRAM / memory telemetry — platform-specific polling with CPU-only fallback.
//!
//! # Supported backends
//!
//! | Platform | Feature | Mechanism |
//! |----------|---------|-----------|
//! | macOS | any | `mach_task_basic_info` + `IOReport` (via `libc`) |
//! | Linux | `cuda` | `nvml-wrapper` (GPU VRAM) + `/proc/meminfo` (system RAM) |
//! | All | — | `sysinfo`-style `/proc/meminfo` or `sysctl hw.memsize` fallback |
//!
//! ## Usage
//!
//! ```no_run
//! use libnclaw::llm::telemetry::{MemorySnapshot, poll_memory};
//!
//! let snap = poll_memory();
//! println!("GPU: {}MB, RAM: {}MB", snap.gpu_used_mb, snap.ram_used_mb);
//! ```

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A point-in-time memory usage snapshot.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MemorySnapshot {
    /// GPU VRAM currently in use, in MB.
    ///
    /// `0` when no GPU is present or VRAM telemetry is unavailable.
    pub gpu_used_mb: u64,
    /// Total GPU VRAM, in MB.
    ///
    /// `0` when no GPU is present.
    pub gpu_total_mb: u64,
    /// System RAM currently in use by this process, in MB.
    pub ram_used_mb: u64,
    /// Total system RAM, in MB.
    pub ram_total_mb: u64,
    /// Telemetry source string for diagnostics (e.g. `"macos-mach"`, `"nvml"`, `"proc-meminfo"`).
    pub source: String,
}

// ---------------------------------------------------------------------------
// Top-level poll function — dispatches to platform backend
// ---------------------------------------------------------------------------

/// Collect a memory snapshot using the best available mechanism for the
/// current platform and feature set.
///
/// Never panics. Returns a zero-filled snapshot if all backends fail.
pub fn poll_memory() -> MemorySnapshot {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        poll_macos()
    }

    #[cfg(all(target_os = "linux", feature = "cuda"))]
    {
        poll_linux_nvml().unwrap_or_else(|_| poll_linux_proc())
    }

    #[cfg(all(target_os = "linux", not(feature = "cuda")))]
    {
        poll_linux_proc()
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "linux")))]
    {
        poll_generic()
    }
}

// ---------------------------------------------------------------------------
// macOS backend — mach_task_basic_info + sysctl
// ---------------------------------------------------------------------------

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn poll_macos() -> MemorySnapshot {
    let ram_used_mb = macos_resident_mb().unwrap_or(0);
    let ram_total_mb = macos_total_mb().unwrap_or(0);

    // GPU VRAM on Apple Silicon is unified memory. IOReport-based telemetry
    // requires private frameworks not available in non-sandboxed processes
    // without entitlements. We report 0 for GPU VRAM on macOS as a safe
    // default — the UI should display "Unified" instead of separate GPU bars.
    MemorySnapshot {
        gpu_used_mb: 0,
        gpu_total_mb: 0,
        ram_used_mb,
        ram_total_mb,
        source: "macos-mach".into(),
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn macos_resident_mb() -> Option<u64> {
    #[repr(C)]
    struct MachTaskBasicInfo {
        virtual_size: u64,
        resident_size: u64,
        resident_size_max: u64,
        user_time: (u32, u32),
        system_time: (u32, u32),
        policy: i32,
        suspend_count: i32,
    }

    const MACH_TASK_BASIC_INFO: u32 = 20;

    let mut info = MachTaskBasicInfo {
        virtual_size: 0,
        resident_size: 0,
        resident_size_max: 0,
        user_time: (0, 0),
        system_time: (0, 0),
        policy: 0,
        suspend_count: 0,
    };
    let mut count = (std::mem::size_of::<MachTaskBasicInfo>() / std::mem::size_of::<u32>()) as u32;

    let rc = unsafe {
        libc::task_info(
            libc::mach_task_self(),
            MACH_TASK_BASIC_INFO,
            &mut info as *mut _ as libc::task_info_t,
            &mut count,
        )
    };

    if rc == libc::KERN_SUCCESS {
        Some(info.resident_size / (1024 * 1024))
    } else {
        None
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn macos_total_mb() -> Option<u64> {
    let mut value: u64 = 0;
    let mut len = std::mem::size_of::<u64>();
    let key = std::ffi::CString::new("hw.memsize").ok()?;
    let rc = unsafe {
        libc::sysctlbyname(
            key.as_ptr(),
            &mut value as *mut u64 as *mut libc::c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        )
    };
    if rc == 0 && value > 0 {
        Some(value / (1024 * 1024))
    } else {
        None
    }
}

// ---------------------------------------------------------------------------
// Linux + CUDA backend — nvml-wrapper
// ---------------------------------------------------------------------------

#[cfg(all(target_os = "linux", feature = "cuda"))]
fn poll_linux_nvml() -> Result<MemorySnapshot, String> {
    // nvml-wrapper is only pulled in when feature = "cuda".
    // The crate is already a transitive dep of llama-cpp-2 in that feature.
    use nvml_wrapper::Nvml;
    let nvml = Nvml::init().map_err(|e| e.to_string())?;
    let device = nvml.device_by_index(0).map_err(|e| e.to_string())?;
    let mem = device.memory_info().map_err(|e| e.to_string())?;

    let proc_snap = poll_linux_proc();
    Ok(MemorySnapshot {
        gpu_used_mb: mem.used / (1024 * 1024),
        gpu_total_mb: mem.total / (1024 * 1024),
        ram_used_mb: proc_snap.ram_used_mb,
        ram_total_mb: proc_snap.ram_total_mb,
        source: "nvml+proc-meminfo".into(),
    })
}

// ---------------------------------------------------------------------------
// Linux CPU-only backend — /proc/meminfo
// ---------------------------------------------------------------------------

#[cfg(target_os = "linux")]
fn poll_linux_proc() -> MemorySnapshot {
    let (total, available) = parse_proc_meminfo().unwrap_or((0, 0));
    let used = total.saturating_sub(available);
    MemorySnapshot {
        gpu_used_mb: 0,
        gpu_total_mb: 0,
        ram_used_mb: used / 1024,
        ram_total_mb: total / 1024,
        source: "proc-meminfo".into(),
    }
}

#[cfg(target_os = "linux")]
fn parse_proc_meminfo() -> Option<(u64, u64)> {
    let contents = std::fs::read_to_string("/proc/meminfo").ok()?;
    let mut total_kb = None;
    let mut available_kb = None;
    for line in contents.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            total_kb = rest.trim().split_whitespace().next().and_then(|v| v.parse().ok());
        }
        if let Some(rest) = line.strip_prefix("MemAvailable:") {
            available_kb = rest.trim().split_whitespace().next().and_then(|v| v.parse().ok());
        }
        if total_kb.is_some() && available_kb.is_some() {
            break;
        }
    }
    Some((total_kb?, available_kb?))
}

// ---------------------------------------------------------------------------
// Generic fallback (Windows, FreeBSD, etc.)
// ---------------------------------------------------------------------------

#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "linux")))]
fn poll_generic() -> MemorySnapshot {
    MemorySnapshot {
        source: "unavailable".into(),
        ..Default::default()
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn poll_returns_a_snapshot() {
        // Just verify it doesn't panic and returns a non-empty source string.
        let snap = poll_memory();
        assert!(!snap.source.is_empty());
    }

    #[test]
    fn snapshot_serde_roundtrip() {
        let snap = MemorySnapshot {
            gpu_used_mb: 512,
            gpu_total_mb: 8192,
            ram_used_mb: 1024,
            ram_total_mb: 16384,
            source: "test".into(),
        };
        let json = serde_json::to_string(&snap).unwrap();
        let back: MemorySnapshot = serde_json::from_str(&json).unwrap();
        assert_eq!(back.gpu_used_mb, 512);
        assert_eq!(back.gpu_total_mb, 8192);
        assert_eq!(back.source, "test");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn linux_proc_meminfo_parse() {
        // Only runs on Linux CI — parse real /proc/meminfo.
        let (total, avail) = super::parse_proc_meminfo().unwrap();
        assert!(total > 0, "MemTotal should be non-zero");
        assert!(avail <= total, "MemAvailable must be <= MemTotal");
    }

    #[cfg(any(target_os = "macos", target_os = "ios"))]
    #[test]
    fn macos_total_nonzero() {
        let mb = super::macos_total_mb();
        assert!(mb.is_some(), "hw.memsize sysctl should succeed on macOS");
        assert!(mb.unwrap() > 0);
    }
}
