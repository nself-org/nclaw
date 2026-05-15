//! Argon2id calibration binary — measures Argon2id derive time on host hardware.
//!
//! Runs a 10-iteration median timing for each profile preset and outputs the
//! recommended profile + calibrated params in TOML format.
//!
//! # Usage
//!
//! ```shell
//! cargo run -p libnclaw --bin argon2_calibrate --release
//! ```
//!
//! # Output
//!
//! Prints a human-readable report to stdout, then writes a TOML profile config to
//! `argon2-calibration.toml` in the current directory.
//!
//! # Profile presets
//!
//! | Profile     | m (MiB) | t | p | Target latency               |
//! |-------------|---------|---|---|------------------------------|
//! | mobile-low  | 32      | 2 | 1 | ~250 ms (iOS A12, entry Android) |
//! | mobile-std  | 64      | 3 | 1 | ~400 ms (A15+, mid-range)     |
//! | desktop     | 128     | 3 | 4 | ~300 ms (8 GB+ desktop)       |

use argon2::{Algorithm, Argon2, Params, Version};
use std::time::{Duration, Instant};

const RUNS: usize = 10;
const PASSPHRASE: &[u8] = b"calibration_passphrase_nclaw_00";
const SALT: &[u8] = b"calibration_salt"; // 16 bytes

/// A hardware-tier profile preset.
struct Profile {
    name: &'static str,
    m_cost_kib: u32,
    t_cost: u32,
    p_cost: u32,
    /// Acceptable upper bound for "recommended" label. Profiles within this
    /// budget on this machine get the green checkmark.
    budget_ms: u128,
}

const PROFILES: &[Profile] = &[
    Profile {
        name: "mobile-low",
        m_cost_kib: 32 * 1024,
        t_cost: 2,
        p_cost: 1,
        budget_ms: 500,
    },
    Profile {
        name: "mobile-std",
        m_cost_kib: 64 * 1024,
        t_cost: 3,
        p_cost: 1,
        budget_ms: 800,
    },
    Profile {
        name: "desktop",
        m_cost_kib: 128 * 1024,
        t_cost: 3,
        p_cost: 4,
        budget_ms: 1000,
    },
];

fn measure(m_cost_kib: u32, t_cost: u32, p_cost: u32) -> Duration {
    let params = Params::new(m_cost_kib, t_cost, p_cost, Some(32))
        .expect("valid argon2 params");
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut durations: Vec<Duration> = (0..RUNS)
        .map(|_| {
            let mut out = [0u8; 32];
            let start = Instant::now();
            argon2
                .hash_password_into(PASSPHRASE, SALT, &mut out)
                .expect("argon2 hash");
            start.elapsed()
        })
        .collect();

    durations.sort();
    durations[RUNS / 2] // median
}

fn main() {
    println!("Argon2id calibration — nclaw profile presets");
    println!("=============================================");
    println!("Runs per profile: {} (reporting median)", RUNS);
    println!();

    let mut recommended: Option<&str> = None;
    let mut results: Vec<(&str, u32, u32, u32, u128)> = Vec::new();

    for profile in PROFILES {
        print!(
            "  [{:<11}] m={:>4} MiB  t={}  p={}  ... ",
            profile.name,
            profile.m_cost_kib / 1024,
            profile.t_cost,
            profile.p_cost,
        );
        // flush so user sees the label before the slow measurement
        use std::io::Write;
        std::io::stdout().flush().ok();

        let median = measure(profile.m_cost_kib, profile.t_cost, profile.p_cost);
        let ms = median.as_millis();
        let ok = ms <= profile.budget_ms;

        println!("{:>5} ms  {}", ms, if ok { "✓" } else { "✗ (over budget)" });

        if ok && recommended.is_none() {
            recommended = Some(profile.name);
        }

        results.push((profile.name, profile.m_cost_kib, profile.t_cost, profile.p_cost, ms));
    }

    println!();

    let recommended_name = recommended.unwrap_or("mobile-low");
    println!("Recommended profile for this hardware: {}", recommended_name);

    // Find the winning profile's params
    let (_, m, t, p, ms) = results
        .iter()
        .find(|(name, ..)| *name == recommended_name)
        .copied()
        .expect("recommended profile in results");

    println!();
    println!("TOML output (written to argon2-calibration.toml):");
    println!("--------------------------------------------------");

    let toml_output = format!(
        r#"# Argon2id calibration result — nclaw
# Generated on this host; re-run `argon2_calibrate` if hardware changes.
# Copy `recommended_profile` into your nclaw config.

[calibration]
runs = {runs}
recommended_profile = "{name}"
measured_ms = {ms}

[profile.mobile-low]
m_cost_kib = {m_low}
t_cost = 2
p_cost = 1

[profile.mobile-std]
m_cost_kib = {m_std}
t_cost = 3
p_cost = 1

[profile.desktop]
m_cost_kib = {m_desk}
t_cost = 3
p_cost = 4
"#,
        runs = RUNS,
        name = recommended_name,
        ms = ms,
        m_low = 32 * 1024u32,
        m_std = 64 * 1024u32,
        m_desk = 128 * 1024u32,
    );

    println!("{}", toml_output);

    std::fs::write("argon2-calibration.toml", &toml_output)
        .expect("write argon2-calibration.toml");

    println!("Written: argon2-calibration.toml");
    println!();
    println!("Recommended profile `{}` derives in {} ms on this device.", recommended_name, ms);
    println!("Use KdfProfile::{} in your nclaw mobile/desktop build.", profile_enum(recommended_name));
}

fn profile_enum(name: &str) -> &str {
    match name {
        "mobile-low" => "MobileLow",
        "mobile-std" => "MobileStd",
        "desktop" => "Desktop",
        other => other,
    }
}
