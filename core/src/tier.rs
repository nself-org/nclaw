//! Tier classifier — pure-function mapping `DeviceProbe → Tier` per Decision #9.
//!
//! No I/O. No async. Takes a `DeviceProbe` and a `TierOverride` and returns a `Tier`.
//! All logic is expressed as `&&` / `||` over fields already present in `DeviceProbe`.

use serde::{Deserialize, Serialize};

use crate::device::DeviceProbe;

/// Hardware capability tier. T0 = minimum, T4 = workstation/flagship (opt-in only).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Tier {
    /// RAM ≤ 4 GB or severely constrained mobile.
    T0,
    /// RAM 5–8 GB, no GPU/Apple Silicon, or basic Android.
    T1,
    /// RAM 9–16 GB, Apple Silicon UMA ≥ 8 GB, or flagship mobile SoC.
    T2,
    /// RAM 17–32 GB with capable GPU/Apple Silicon Pro/Max.
    T3,
    /// RAM ≥ 64 GB with high-VRAM GPU or Apple Silicon Max/Ultra (opt-in only).
    T4,
}

/// Caller-supplied overrides that can force or cap the auto-classified tier.
#[derive(Debug, Clone, Default)]
pub struct TierOverride {
    /// Bypass classification entirely and return this tier.
    pub force_tier: Option<Tier>,
    /// Suppress any in-app upgrade prompt shown to users below their potential tier.
    pub disable_upgrade_prompt: bool,
    /// Must be `true` for `classify_tier` to ever return `Tier::T4`.
    /// T4 is never assigned automatically — it must always be opted into explicitly.
    pub allow_t4: bool,
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Returns `true` when the cpu_brand indicates Apple Silicon Pro, Max, or Ultra.
///
/// Heuristic: brand string contains "Pro", "Max", or "Ultra" (case-sensitive, as
/// Apple uses title-case in sysctl output), OR unified_memory == true with
/// physical_cores ≥ 8 (catches future chips that may ship under a new name).
#[inline]
fn is_apple_pro_max_ultra(probe: &DeviceProbe) -> bool {
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
fn is_flagship_mobile_soc(probe: &DeviceProbe) -> bool {
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

/// Returns `true` when there is a discrete or dedicated GPU with ≥ `min_vram_mb` VRAM.
#[inline]
fn has_vram_at_least(probe: &DeviceProbe, min_vram_mb: u64) -> bool {
    probe.gpu_vram_mb.map(|v| v >= min_vram_mb).unwrap_or(false)
}

// ---------------------------------------------------------------------------
// Public classifier
// ---------------------------------------------------------------------------

/// Classify the device tier from a `DeviceProbe` and an optional `TierOverride`.
///
/// Decision matrix (Decision #9):
///
/// | Condition | Tier |
/// |---|---|
/// | `force_tier` set | that tier (bypasses all logic) |
/// | RAM ≤ 4 GB | T0 |
/// | Mobile && not flagship SoC | T0 if RAM ≤ 4 GB, else T1 (capped at T2 max even for flagship) |
/// | RAM 5–8 GB && no GPU && not Apple Silicon | T1 |
/// | Apple Silicon UMA && RAM ≥ 8 GB | T2 |
/// | RAM 9–16 GB | T2 |
/// | RAM 17–32 GB && (VRAM ≥ 8 GB \|\| Apple Silicon Pro/Max) | T3 |
/// | RAM ≥ 64 GB && (VRAM ≥ 16 GB \|\| Apple Silicon Max/Ultra) | T4 (only if `allow_t4`) |
/// | Conditions met for T4 but `allow_t4 == false` | T3 |
///
/// Mobile devices (os == "ios" \|\| os == "android") are capped at T2 regardless of RAM,
/// unless they have a flagship SoC — in which case they still max at T2 (mobile GPU is
/// shared and cannot run models requiring T3+ VRAM).
pub fn classify_tier(probe: &DeviceProbe, ovr: &TierOverride) -> Tier {
    // --- Override: force_tier bypasses all classification logic ---
    if let Some(forced) = ovr.force_tier {
        return forced;
    }

    let ram = probe.ram_total_mb;
    let is_mobile = probe.os == "ios" || probe.os == "android";
    let has_apple_silicon = probe.apple_silicon;
    let is_pro_max_ultra = is_apple_pro_max_ultra(probe);

    // --- T4 check (highest; must come before T3 so we can cap correctly) ---
    // Condition: RAM ≥ 64 GB AND (VRAM ≥ 16 GB OR Apple Silicon Max/Ultra)
    let t4_conditions =
        ram >= 64 * 1024 && (has_vram_at_least(probe, 16 * 1024) || is_pro_max_ultra);
    if t4_conditions && !is_mobile {
        return if ovr.allow_t4 { Tier::T4 } else { Tier::T3 };
    }

    // --- T0: hard floor ---
    if ram <= 4 * 1024 {
        return Tier::T0;
    }

    // --- Mobile cap: max T2 regardless of RAM/VRAM ---
    // Flagship mobile SoC gets T2; everything else gets T1 (5–8 GB) or T0 (already caught).
    if is_mobile {
        return if is_flagship_mobile_soc(probe) {
            Tier::T2
        } else {
            // Non-flagship mobile: 5–8 GB → T1; > 8 GB still capped at T2
            // (future high-RAM Android tablets without a flagship SoC stay at T1
            // to avoid over-promising model performance)
            if ram <= 8 * 1024 {
                Tier::T1
            } else {
                Tier::T2
            }
        };
    }

    // --- T3: RAM 17–32 GB with capable GPU or Apple Silicon Pro/Max ---
    if ram >= 17 * 1024 && ram < 64 * 1024 {
        let meets_t3 = has_vram_at_least(probe, 8 * 1024) || is_pro_max_ultra;
        if meets_t3 {
            return Tier::T3;
        }
        // High RAM but insufficient GPU → fall through to T2
    }

    // --- T2: Apple Silicon UMA ≥ 8 GB OR RAM 9–16 GB ---
    if (has_apple_silicon && probe.unified_memory && ram >= 8 * 1024) || ram >= 9 * 1024 {
        return Tier::T2;
    }

    // --- T1: RAM 5–8 GB, no qualifying GPU, not Apple Silicon ---
    // (also catches RAM 17–32 GB with no GPU/Apple Silicon that fell through T3)
    Tier::T1
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn probe(
        os: &str,
        cpu_brand: &str,
        physical_cores: u32,
        ram_gb: u64,
        apple_silicon: bool,
        unified_memory: bool,
        gpu_vram_gb: Option<u64>,
    ) -> DeviceProbe {
        DeviceProbe {
            os: os.into(),
            arch: if apple_silicon { "aarch64" } else { "x86_64" }.into(),
            cpu_brand: cpu_brand.into(),
            physical_cores,
            logical_cores: physical_cores * 2,
            ram_total_mb: ram_gb * 1024,
            gpu_vendor: gpu_vram_gb.map(|_| "NVIDIA".into()),
            gpu_vram_mb: gpu_vram_gb.map(|g| g * 1024),
            apple_silicon,
            unified_memory,
            low_power_mode: false,
        }
    }

    fn no_ovr() -> TierOverride {
        TierOverride::default()
    }

    fn allow_t4() -> TierOverride {
        TierOverride {
            allow_t4: true,
            ..Default::default()
        }
    }

    // -------------------------------------------------------------------------
    // T0 cases
    // -------------------------------------------------------------------------

    #[test]
    fn t0_old_netbook_4gb_no_gpu() {
        let p = probe("linux", "Intel Celeron N4020", 2, 4, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T0);
    }

    #[test]
    fn t0_iphone_12_4gb_a14() {
        // A14 is not in the flagship SoC list (A17/A18/M-series only)
        let p = probe("ios", "Apple A14 Bionic", 6, 4, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T0);
    }

    #[test]
    fn t0_windows_4gb_integrated_gpu() {
        let p = probe("windows", "Intel Core i3-1115G4", 2, 4, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T0);
    }

    #[test]
    fn t0_android_3gb_budget() {
        let p = probe("android", "Snapdragon 680", 8, 3, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T0);
    }

    // -------------------------------------------------------------------------
    // T1 cases
    // -------------------------------------------------------------------------

    #[test]
    fn t1_mid_android_8gb_non_flagship() {
        // 8 GB Android, Snapdragon 7s Gen 2 — not flagship
        let p = probe("android", "Snapdragon 7s Gen 2", 8, 8, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T1);
    }

    #[test]
    fn t1_8gb_intel_laptop_no_gpu() {
        let p = probe("linux", "Intel Core i5-1135G7", 4, 8, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T1);
    }

    #[test]
    fn t1_8gb_windows_no_discrete_gpu() {
        let p = probe("windows", "AMD Ryzen 5 5500U", 6, 8, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T1);
    }

    #[test]
    fn t1_6gb_linux_no_gpu() {
        let p = probe("linux", "Intel Core i3-8100", 4, 6, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T1);
    }

    // -------------------------------------------------------------------------
    // T2 cases
    // -------------------------------------------------------------------------

    #[test]
    fn t2_m1_air_16gb() {
        let p = probe("macos", "Apple M1", 8, 16, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn t2_m1_macbook_8gb() {
        // Apple Silicon UMA ≥ 8 GB → T2 even at 8 GB
        let p = probe("macos", "Apple M1", 8, 8, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn t2_iphone_15_a17_pro_flagship_mobile() {
        // Flagship SoC (A17) on mobile → capped at T2
        let p = probe("ios", "Apple A17 Pro", 6, 8, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn t2_iphone_16_pro_a18_pro() {
        let p = probe("ios", "Apple A18 Pro", 6, 8, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn t2_12gb_linux_no_gpu() {
        // 9–16 GB without Apple Silicon → T2
        let p = probe("linux", "Intel Core i7-1185G7", 4, 12, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn t2_16gb_windows_integrated_only() {
        let p = probe("windows", "AMD Ryzen 7 5700U", 8, 16, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn t2_ipad_pro_m4_flagship_soc_mobile_cap() {
        // M4 on iOS (iPad Pro) — flagship but still mobile → cap at T2
        let p = probe("ios", "Apple M4", 10, 16, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    // -------------------------------------------------------------------------
    // T3 cases
    // -------------------------------------------------------------------------

    #[test]
    fn t3_16gb_rtx3050_8gb_vram() {
        let p = probe(
            "linux",
            "Intel Core i7-12700H",
            14,
            16,
            false,
            false,
            Some(8),
        );
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T3);
    }

    #[test]
    fn t3_m2_pro_32gb() {
        let p = probe("macos", "Apple M2 Pro", 12, 32, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T3);
    }

    #[test]
    fn t3_m2_max_64gb_allow_t4_false() {
        // M2 Max with 64 GB but allow_t4 == false → capped at T3
        let p = probe("macos", "Apple M2 Max", 12, 64, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T3);
    }

    #[test]
    fn t3_32gb_rtx3080_12gb_vram() {
        let p = probe(
            "windows",
            "Intel Core i9-12900K",
            16,
            32,
            false,
            false,
            Some(12),
        );
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T3);
    }

    #[test]
    fn t3_m3_pro_36gb() {
        let p = probe("macos", "Apple M3 Pro", 12, 36, true, true, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T3);
    }

    // -------------------------------------------------------------------------
    // T4 cases (require allow_t4 == true)
    // -------------------------------------------------------------------------

    #[test]
    fn t4_m2_max_64gb_allow_t4_true() {
        let p = probe("macos", "Apple M2 Max", 12, 64, true, true, None);
        assert_eq!(classify_tier(&p, &allow_t4()), Tier::T4);
    }

    #[test]
    fn t4_m3_ultra_192gb() {
        let p = probe("macos", "Apple M3 Ultra", 24, 192, true, true, None);
        assert_eq!(classify_tier(&p, &allow_t4()), Tier::T4);
    }

    #[test]
    fn t4_workstation_256gb_2x_rtx4090() {
        // 48 GB total VRAM modelled as a single gpu_vram_mb (48 GB)
        let p = probe(
            "linux",
            "AMD Threadripper PRO 5975WX",
            32,
            256,
            false,
            false,
            Some(48),
        );
        assert_eq!(classify_tier(&p, &allow_t4()), Tier::T4);
    }

    #[test]
    fn t4_linux_64gb_a100_40gb_vram() {
        let p = probe("linux", "AMD EPYC 7742", 64, 256, false, false, Some(40));
        assert_eq!(classify_tier(&p, &allow_t4()), Tier::T4);
    }

    // -------------------------------------------------------------------------
    // force_tier override
    // -------------------------------------------------------------------------

    #[test]
    fn force_tier_overrides_any_probe() {
        // Weak netbook forced to T3
        let p = probe("linux", "Intel Celeron N4020", 2, 4, false, false, None);
        let ovr = TierOverride {
            force_tier: Some(Tier::T3),
            ..Default::default()
        };
        assert_eq!(classify_tier(&p, &ovr), Tier::T3);
    }

    #[test]
    fn force_tier_t0_on_flagship() {
        // M2 Ultra forced down to T0
        let p = probe("macos", "Apple M2 Ultra", 24, 192, true, true, None);
        let ovr = TierOverride {
            force_tier: Some(Tier::T0),
            allow_t4: true,
            ..Default::default()
        };
        assert_eq!(classify_tier(&p, &ovr), Tier::T0);
    }

    // -------------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------------

    #[test]
    fn edge_exactly_4gb_is_t0() {
        let p = probe("linux", "Intel Celeron", 2, 4, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T0);
    }

    #[test]
    fn edge_5gb_no_gpu_is_t1() {
        let p = probe("linux", "Intel Core i3", 2, 5, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T1);
    }

    #[test]
    fn edge_9gb_no_gpu_is_t2() {
        let p = probe("linux", "Intel Core i5", 4, 9, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn edge_17gb_no_gpu_no_apple_silicon_is_t2() {
        // 17 GB but no GPU and no Apple Silicon → T3 conditions not met → T2
        let p = probe("linux", "Intel Core i7", 8, 17, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn edge_t4_not_granted_without_allow_flag() {
        // Even enormous RAM + VRAM stays T3 without allow_t4
        let p = probe("linux", "AMD EPYC 7742", 64, 512, false, false, Some(80));
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T3);
    }

    #[test]
    fn edge_snapdragon_8_gen_3_android_high_ram() {
        // Flagship Android SoC — still mobile cap T2 even with 12 GB
        let p = probe("android", "Snapdragon 8 Gen 3", 8, 12, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T2);
    }

    #[test]
    fn edge_snapdragon_8_gen_2_not_flagship() {
        // "8 Gen 2" must NOT match the flagship heuristic
        let p = probe("android", "Snapdragon 8 Gen 2", 8, 8, false, false, None);
        assert_eq!(classify_tier(&p, &no_ovr()), Tier::T1);
    }

    #[test]
    fn edge_apple_silicon_uma_8_cores_fallback() {
        // No "Pro/Max/Ultra" in brand string, but UMA + 8 physical cores → is_pro_max_ultra true
        // With 64 GB this qualifies for T4 when allowed
        let p = probe("macos", "Apple M-future-chip", 8, 64, true, true, None);
        assert_eq!(classify_tier(&p, &allow_t4()), Tier::T4);
    }
}
