//! Internal helper predicates for tier classification.
//!
//! All functions take a `DeviceProbe` reference and return a `bool`.
//! These predicates are pure (no I/O, no state mutation) and kept
//! in a separate module to keep the main classifier readable.

use crate::device::DeviceProbe;

/// Returns `true` when the cpu_brand indicates Apple Silicon Pro, Max, or Ultra.
///
/// Heuristic: brand string contains "Pro", "Max", or "Ultra" (case-sensitive, as
/// Apple uses title-case in sysctl output), OR unified_memory == true with
/// physical_cores >= 8 (catches future chips that may ship under a new name).
#[inline]
pub(super) fn is_apple_pro_max_ultra(probe: &DeviceProbe) -> bool {
    if probe.apple_silicon {
        let brand = &probe.cpu_brand;
        if brand.contains("Pro") || brand.contains("Max") || brand.contains("Ultra") {
            return true;
        }
        // Fallback: UMA + high core count = likely Pro or better
        if probe.unified_memory && probe.physical_cores >= 8 {
            return true;
        }
    }
    false
}

/// Returns `true` when the device is a mobile (iOS or Android) flagship SoC.
///
/// Recognised chip strings (case-sensitive, matching Apple/Qualcomm product names):
/// - Apple: A17, A18, M1, M2, M3, M4 (on iPad Pro / iPhone Pro)
/// - Qualcomm: Snapdragon 8 Gen 3 (and future "8 Gen 4+" via prefix "8 Gen ")
///   filtered to Gen 3+.
#[inline]
pub(super) fn is_flagship_mobile_soc(probe: &DeviceProbe) -> bool {
    let brand = &probe.cpu_brand;
    // Apple A17 / A18 SoCs (iPhone Pro lines)
    if brand.contains("A17") || brand.contains("A18") {
        return true;
    }
    // Apple M-series in iPad Pro (M1–M4)
    if probe.apple_silicon
        && (brand.contains("M1")
            || brand.contains("M2")
            || brand.contains("M3")
            || brand.contains("M4"))
    {
        return true;
    }
    // Snapdragon 8 Gen 3+ (cheap string: "8 Gen 3", "8 Gen 4", etc.)
    // We do not want to catch "8 Gen 2" or "8 Gen 1".
    if brand.contains("Snapdragon 8 Gen 3")
        || brand.contains("Snapdragon 8 Gen 4")
        || brand.contains("Snapdragon 8 Gen 5")
    {
        return true;
    }
    false
}

/// Returns `true` when there is a discrete or dedicated GPU with >= `min_vram_mb` VRAM.
#[inline]
pub(super) fn has_vram_at_least(probe: &DeviceProbe, min_vram_mb: u64) -> bool {
    probe.gpu_vram_mb.map(|v| v >= min_vram_mb).unwrap_or(false)
}
