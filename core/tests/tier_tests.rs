//! Integration test suite for tier::classify_tier — 34 scenarios covering Decision #9.
//!
//! Moved here from src/tier/mod.rs to keep the source module under the 300-line cap.

use libnclaw::device::DeviceProbe;
use libnclaw::tier::{classify_tier, Tier, TierOverride};

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
