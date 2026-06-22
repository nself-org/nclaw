//! Tier classifier — pure-function mapping `DeviceProbe → Tier` per Decision #9.
//!
//! No I/O. No async. Takes a `DeviceProbe` and a `TierOverride` and returns a `Tier`.
//! All logic is expressed as `&&` / `||` over fields already present in `DeviceProbe`.
//!
//! Internal predicates live in `helpers` to keep this module under the 300-line cap.

mod helpers;

use helpers::{has_vram_at_least, is_apple_pro_max_ultra, is_flagship_mobile_soc};
use serde::{Deserialize, Serialize};

use crate::device::DeviceProbe;

/// Hardware capability tier. T0 = minimum, T4 = workstation/flagship (opt-in only).
///
/// # Mapping from legacy `Tier::Basic` / `Tier::Free`
///
/// Prior to the numeric T0–T4 reorganization, this enum used named variants
/// (`Basic`, `Free`, etc.). The canonical mapping for legacy call sites:
///
/// | Legacy variant | New variant | Rationale |
/// |---|---|---|
/// | `Tier::Free`  | `Tier::T0` | Minimum hardware tier. Licensing/free-tier concerns are now handled separately via license checks, not via the tier enum. |
/// | `Tier::Basic` | `Tier::T1` | "Below-flagship" hardware: 5–8 GB RAM, no discrete GPU, no Apple Silicon. The router treats T0/T1 identically for Code workloads (both insufficient — score penalty applies). |
///
/// # Routing-score implications (see `bridge::router::Router::score`)
///
/// The router uses `Tier` to gate local inference quality:
/// - `T0` / `T1`: insufficient for `PromptClass::Code` → score -30 on Local route.
/// - `T2`+: capable of any workload locally.
///
/// Routing tests should pick the tier deliberately:
/// - Use `T1` (or `T0`) when validating "weak local hardware prefers cloud routes".
/// - Use `T2`+ when validating "capable local hardware prefers local routes".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Tier {
    /// RAM <= 4 GB or severely constrained mobile.
    T0,
    /// RAM 5–8 GB, no GPU/Apple Silicon, or basic Android.
    T1,
    /// RAM 9–15 GB, or RAM 16+ GB without a capable discrete GPU / Apple Silicon Pro+,
    /// Apple Silicon UMA >= 8 GB, or flagship mobile SoC.
    T2,
    /// RAM >= 16 GB with capable discrete GPU (>= 8 GB VRAM) OR Apple Silicon Pro/Max.
    /// Threshold is 16 GB (not 17) because a discrete >=8 GB-VRAM GPU paired with 16 GB
    /// system RAM (e.g. RTX 3050 + 16 GB DDR4 gaming laptop) is genuinely T3-class for
    /// local-model inference: VRAM is dedicated, system RAM is not contended by GPU.
    /// Apple Silicon Pro/Max also enters T3 via UMA (RAM doubles as GPU memory).
    T3,
    /// RAM >= 64 GB with high-VRAM GPU or Apple Silicon Max/Ultra (opt-in only).
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

/// Classify the device tier from a `DeviceProbe` and an optional `TierOverride`.
///
/// Decision matrix (Decision #9):
///
/// | Condition | Tier |
/// |---|---|
/// | `force_tier` set | that tier (bypasses all logic) |
/// | RAM <= 4 GB | T0 |
/// | Mobile && not flagship SoC | T0 if RAM <= 4 GB, else T1 (capped at T2 max even for flagship) |
/// | RAM 5–8 GB && no GPU && not Apple Silicon | T1 |
/// | Apple Silicon UMA && RAM >= 8 GB | T2 |
/// | RAM 9–15 GB | T2 |
/// | RAM 16–63 GB && VRAM >= 8 GB (discrete GPU path) | T3 |
/// | RAM 17–63 GB && Apple Silicon Pro/Max (UMA path; higher floor since RAM is shared) | T3 |
/// | RAM 16–63 GB && no qualifying GPU AND not Apple Silicon Pro/Max | T2 |
/// | RAM >= 64 GB && (VRAM >= 16 GB || Apple Silicon Max/Ultra) | T4 (only if `allow_t4`) |
/// | Conditions met for T4 but `allow_t4 == false` | T3 |
///
/// Mobile devices (os == "ios" || os == "android") are capped at T2 regardless of RAM,
/// unless they have a flagship SoC — in which case they still max at T2 (mobile GPU is
/// shared and cannot run models requiring T3+ VRAM).
pub fn classify_tier(probe: &DeviceProbe, ovr: &TierOverride) -> Tier {
    if let Some(forced) = ovr.force_tier {
        return forced;
    }

    let ram = probe.ram_total_mb;
    let is_mobile = probe.os == "ios" || probe.os == "android";
    let has_apple_silicon = probe.apple_silicon;
    let is_pro_max_ultra = is_apple_pro_max_ultra(probe);

    // T4 check (highest; must come before T3 so we can cap correctly).
    // Condition: RAM >= 64 GB AND (VRAM >= 16 GB OR Apple Silicon Max/Ultra).
    let t4_conditions =
        ram >= 64 * 1024 && (has_vram_at_least(probe, 16 * 1024) || is_pro_max_ultra);
    if t4_conditions && !is_mobile {
        return if ovr.allow_t4 { Tier::T4 } else { Tier::T3 };
    }

    // T0: hard floor.
    if ram <= 4 * 1024 {
        return Tier::T0;
    }

    // Mobile cap: max T2 regardless of RAM/VRAM.
    // Flagship mobile SoC gets T2; everything else gets T1 (5–8 GB) or T0 (already caught).
    if is_mobile {
        return if is_flagship_mobile_soc(probe) {
            Tier::T2
        } else if ram <= 8 * 1024 {
            Tier::T1
        } else {
            Tier::T2
        };
    }

    // T3: Two qualifying paths.
    // (a) Discrete-GPU path: RAM >= 16 GB AND VRAM >= 8 GB.
    // (b) Apple Silicon UMA path: RAM >= 17 GB AND Apple Silicon Pro/Max.
    if ram < 64 * 1024 {
        let discrete_gpu_t3 = ram >= 16 * 1024 && has_vram_at_least(probe, 8 * 1024);
        let apple_silicon_t3 = ram >= 17 * 1024 && is_pro_max_ultra;
        if discrete_gpu_t3 || apple_silicon_t3 {
            return Tier::T3;
        }
    }

    // T2: Apple Silicon UMA >= 8 GB OR RAM 9–15 GB OR 16+ GB without qualifying GPU.
    if (has_apple_silicon && probe.unified_memory && ram >= 8 * 1024) || ram >= 9 * 1024 {
        return Tier::T2;
    }

    // T1: RAM 5–8 GB, no qualifying GPU, not Apple Silicon.
    Tier::T1
}


