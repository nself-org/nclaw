//! Hardware compute backend auto-selection based on device probe.
//!
//! Pure function matching Decision #9 rules for selecting optimal compute backend.

use serde::{Deserialize, Serialize};

/// Compute backend enum for model inference.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ComputeBackend {
    /// Apple Metal (macOS, iOS)
    Metal,
    /// NVIDIA CUDA
    Cuda,
    /// Cross-platform Vulkan
    Vulkan,
    /// AMD ROCm
    Rocm,
    /// CPU fallback
    Cpu,
}

impl std::fmt::Display for ComputeBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ComputeBackend::Metal => write!(f, "Metal"),
            ComputeBackend::Cuda => write!(f, "CUDA"),
            ComputeBackend::Vulkan => write!(f, "Vulkan"),
            ComputeBackend::Rocm => write!(f, "ROCm"),
            ComputeBackend::Cpu => write!(f, "CPU"),
        }
    }
}

/// Select the optimal compute backend based on device probe.
///
/// Decision #9 rules:
/// - Apple Silicon (macOS/iOS) → Metal (no fallback)
/// - NVIDIA GPU → CUDA (with Vulkan + CPU fallback)
/// - AMD GPU → ROCm on Linux, Vulkan on Windows
/// - Intel GPU → Vulkan
/// - Android → Vulkan
/// - Default → CPU
pub fn select_compute_backend(probe: &crate::device::DeviceProbe) -> ComputeBackend {
    // Rule 1: Apple Silicon (macOS or iOS) → Metal (no fallback)
    if probe.apple_silicon && (probe.os == "macos" || probe.os == "ios") {
        return ComputeBackend::Metal;
    }

    // Rule 2: Check GPU vendor if present
    if let Some(vendor) = &probe.gpu_vendor {
        let vendor_lower = vendor.to_ascii_lowercase();

        // NVIDIA → CUDA
        if vendor_lower.contains("nvidia") {
            return ComputeBackend::Cuda;
        }

        // AMD → ROCm (Linux) or Vulkan (Windows)
        if vendor_lower.contains("amd") || vendor_lower.contains("radeon") {
            if probe.os == "linux" {
                return ComputeBackend::Rocm;
            }
            return ComputeBackend::Vulkan;
        }

        // Intel → Vulkan
        if vendor_lower.contains("intel") {
            return ComputeBackend::Vulkan;
        }

        // Apple GPU → Metal (fallback, already handled above)
        if vendor_lower.contains("apple") {
            return ComputeBackend::Metal;
        }
    }

    // Rule 3: Android → Vulkan
    if probe.os == "android" {
        return ComputeBackend::Vulkan;
    }

    // Default fallback → CPU
    ComputeBackend::Cpu
}

/// Get the fallback chain for a given backend.
///
/// If the primary backend fails, try alternates in order.
/// Metal has no fallback (will fail hard on Apple platforms if unavailable).
pub fn fallback_chain(initial: ComputeBackend) -> &'static [ComputeBackend] {
    match initial {
        ComputeBackend::Metal => &[ComputeBackend::Metal],
        ComputeBackend::Cuda => &[
            ComputeBackend::Cuda,
            ComputeBackend::Vulkan,
            ComputeBackend::Cpu,
        ],
        ComputeBackend::Vulkan => &[ComputeBackend::Vulkan, ComputeBackend::Cpu],
        ComputeBackend::Rocm => &[
            ComputeBackend::Rocm,
            ComputeBackend::Vulkan,
            ComputeBackend::Cpu,
        ],
        ComputeBackend::Cpu => &[ComputeBackend::Cpu],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device::DeviceProbe;

    fn probe_with_os(os: &str) -> DeviceProbe {
        DeviceProbe {
            os: os.into(),
            ..Default::default()
        }
    }

    fn probe_with_gpu(os: &str, gpu_vendor: &str, apple_silicon: bool) -> DeviceProbe {
        DeviceProbe {
            os: os.into(),
            gpu_vendor: Some(gpu_vendor.into()),
            apple_silicon,
            ..Default::default()
        }
    }

    #[test]
    fn test_apple_silicon_macos_metal() {
        let probe = DeviceProbe {
            os: "macos".into(),
            apple_silicon: true,
            ..Default::default()
        };
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Metal);
    }

    #[test]
    fn test_apple_silicon_ios_metal() {
        let probe = DeviceProbe {
            os: "ios".into(),
            apple_silicon: true,
            ..Default::default()
        };
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Metal);
    }

    #[test]
    fn test_nvidia_gpu_cuda() {
        let probe = probe_with_gpu("linux", "NVIDIA GeForce RTX 4090", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Cuda);
    }

    #[test]
    fn test_nvidia_gpu_windows_cuda() {
        let probe = probe_with_gpu("windows", "NVIDIA", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Cuda);
    }

    #[test]
    fn test_amd_gpu_linux_rocm() {
        let probe = probe_with_gpu("linux", "AMD Radeon RX 7900 XT", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Rocm);
    }

    #[test]
    fn test_amd_gpu_windows_vulkan() {
        let probe = probe_with_gpu("windows", "AMD Radeon RX 7900 XT", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Vulkan);
    }

    #[test]
    fn test_intel_gpu_vulkan() {
        let probe = probe_with_gpu("linux", "Intel Iris Graphics", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Vulkan);
    }

    #[test]
    fn test_android_vulkan() {
        let probe = probe_with_os("android");
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Vulkan);
    }

    #[test]
    fn test_no_gpu_linux_cpu() {
        let probe = probe_with_os("linux");
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Cpu);
    }

    #[test]
    fn test_intel_mac_no_gpu_cpu() {
        let probe = DeviceProbe {
            os: "macos".into(),
            apple_silicon: false,
            gpu_vendor: None,
            ..Default::default()
        };
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Cpu);
    }

    #[test]
    fn test_fallback_chain_metal() {
        let chain = fallback_chain(ComputeBackend::Metal);
        assert_eq!(chain, &[ComputeBackend::Metal]);
    }

    #[test]
    fn test_fallback_chain_cuda() {
        let chain = fallback_chain(ComputeBackend::Cuda);
        assert_eq!(
            chain,
            &[
                ComputeBackend::Cuda,
                ComputeBackend::Vulkan,
                ComputeBackend::Cpu
            ]
        );
    }

    #[test]
    fn test_fallback_chain_vulkan() {
        let chain = fallback_chain(ComputeBackend::Vulkan);
        assert_eq!(chain, &[ComputeBackend::Vulkan, ComputeBackend::Cpu]);
    }

    #[test]
    fn test_fallback_chain_rocm() {
        let chain = fallback_chain(ComputeBackend::Rocm);
        assert_eq!(
            chain,
            &[
                ComputeBackend::Rocm,
                ComputeBackend::Vulkan,
                ComputeBackend::Cpu
            ]
        );
    }

    #[test]
    fn test_fallback_chain_cpu() {
        let chain = fallback_chain(ComputeBackend::Cpu);
        assert_eq!(chain, &[ComputeBackend::Cpu]);
    }

    #[test]
    fn test_nvidia_lowercase() {
        let probe = probe_with_gpu("linux", "nvidia", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Cuda);
    }

    #[test]
    fn test_gpu_vendor_case_insensitive() {
        let probe = probe_with_gpu("linux", "NvIdIa", false);
        assert_eq!(select_compute_backend(&probe), ComputeBackend::Cuda);
    }
}
