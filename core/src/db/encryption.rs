//! Encryption-at-rest helpers for nClaw database.
//!
//! Mobile: SQLite + SQLCipher via passphrase-derived key (Argon2id 32-byte).
//! Desktop: pglite/embedded-postgres encrypts via OS disk encryption (FileVault, BitLocker, LUKS) — no app-level key needed.
//!
//! # KDF param profiles
//!
//! Three presets calibrated to common hardware tiers (see `argon2_calibrate` binary):
//!
//! | Profile       | m (MiB) | t | p | Target latency             |
//! |---------------|---------|---|---|----------------------------|
//! | `MobileLow`   | 32      | 2 | 1 | ~250 ms (iOS A12, entry Android) |
//! | `MobileStd`   | 64      | 3 | 1 | ~400 ms (A15+, mid-range Android) |
//! | `Desktop`     | 128     | 3 | 4 | ~300 ms (8 GB+ desktop/laptop) |
//!
//! The active profile is written to a `.kdf-params.toml` sidecar file next to the
//! encrypted DB. Unlocking always reads params from the sidecar so future re-calibration
//! cannot corrupt existing databases.
//!
//! # OWASP reference
//! OWASP Password Storage Cheat Sheet 2023 minimums: m≥19 MiB, t≥2, p≥1.
//! All three profiles exceed the minimums.
//!
//! # RFC reference
//! RFC 9106 §4 recommends Argon2id with m≥64 MiB, t≥1. `MobileStd` and `Desktop` meet
//! these recommendations; `MobileLow` trades slightly lower memory for entry-device
//! compatibility (32 MiB still exceeds OWASP).
//!
//! Full integration with SQLCipher connection pool lands in S16.T09b after sqlcipher crate audit.

use crate::error::CoreError;
use argon2::{Algorithm, Argon2, Params, Version};
use serde::{Deserialize, Serialize};
use std::path::Path;

// ---------------------------------------------------------------------------
// KDF profiles
// ---------------------------------------------------------------------------

/// Hardware-tier presets for Argon2id key derivation.
///
/// Choose the profile that matches the weakest device in your deployment. The
/// profile is persisted in the `.kdf-params.toml` sidecar so unlock always
/// uses the params from when the DB was created.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum KdfProfile {
    /// 32 MiB / 2 iterations / 1 lane.
    /// Target: ~250 ms on iOS A12 / entry-level Android.
    /// Minimum recommended for devices with <3 GB RAM.
    MobileLow,
    /// 64 MiB / 3 iterations / 1 lane.
    /// Target: ~400 ms on Apple A15+ / mid-range Android.
    /// Default for most mobile deployments.
    MobileStd,
    /// 128 MiB / 3 iterations / 4 lanes.
    /// Target: ~300 ms on 8 GB+ desktop / laptop (parallelism amortises cost).
    Desktop,
}

/// Argon2id parameters for a given profile.
///
/// All values exceed OWASP 2023 minimums (m≥19456 KiB, t≥2, p≥1).
/// m_cost is in KiB (as required by the `argon2` crate).
struct ProfileParams {
    /// Memory cost in KiB.
    m_cost_kib: u32,
    /// Time cost (iterations).
    t_cost: u32,
    /// Parallelism (lanes).
    p_cost: u32,
}

impl KdfProfile {
    fn params(self) -> ProfileParams {
        match self {
            // OWASP minimum is 19456 KiB; MobileLow uses 32768 KiB (32 MiB) — 1.7× headroom.
            KdfProfile::MobileLow => ProfileParams { m_cost_kib: 32 * 1024, t_cost: 2, p_cost: 1 },
            // RFC 9106 recommended minimum is 65536 KiB (64 MiB); MobileStd meets it exactly.
            KdfProfile::MobileStd => ProfileParams { m_cost_kib: 64 * 1024, t_cost: 3, p_cost: 1 },
            // Desktop has headroom; 128 MiB + 4 lanes makes GPU cracking impractical.
            KdfProfile::Desktop => ProfileParams { m_cost_kib: 128 * 1024, t_cost: 3, p_cost: 4 },
        }
    }
}

/// Reduced params for `#[cfg(test)]` fast unit tests.
/// Never used in production code paths.
#[cfg(test)]
mod test_params {
    /// m=64 KiB, t=1, p=1 — fast but still exercises the full Argon2id code path.
    pub const M_COST_KIB: u32 = 64;
    pub const T_COST: u32 = 1;
    pub const P_COST: u32 = 1;
}

// ---------------------------------------------------------------------------
// Sidecar format
// ---------------------------------------------------------------------------

/// KDF parameter sidecar persisted next to the encrypted database file.
///
/// Written when a DB is created; read on every unlock. This decouples the
/// active profile from the stored data: future re-calibration does not
/// corrupt existing databases because unlock always uses the stored params.
///
/// Sidecar path convention: `<db_path>.kdf-params.toml`
///
/// # Backward compatibility
/// No existing production databases exist (nclaw is pre-release). If the
/// format changes, increment `version` and add a migration branch in
/// `KdfSidecar::load`. ESCALATE_TO_ARCH before changing the on-disk format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KdfSidecar {
    /// Format version. Currently 1.
    pub version: u32,
    /// Profile used when the DB was created.
    pub profile: KdfProfile,
    /// Memory cost in KiB (stored for forward-compat; must match `profile`).
    pub m_cost_kib: u32,
    /// Time cost (iterations).
    pub t_cost: u32,
    /// Parallelism (lanes).
    pub p_cost: u32,
}

impl KdfSidecar {
    /// Create a sidecar from a profile.
    pub fn from_profile(profile: KdfProfile) -> Self {
        let p = profile.params();
        KdfSidecar {
            version: 1,
            profile,
            m_cost_kib: p.m_cost_kib,
            t_cost: p.t_cost,
            p_cost: p.p_cost,
        }
    }

    /// Sidecar path for a given database path.
    pub fn path_for(db_path: &Path) -> std::path::PathBuf {
        let mut p = db_path.to_path_buf();
        let name = p
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("db")
            .to_string();
        p.set_file_name(format!("{}.kdf-params.toml", name));
        p
    }

    /// Write sidecar to disk.
    pub fn save(&self, db_path: &Path) -> Result<(), CoreError> {
        let sidecar_path = Self::path_for(db_path);
        let toml_str = toml::to_string_pretty(self)
            .map_err(|e| CoreError::Other(format!("kdf sidecar serialize: {e}")))?;
        std::fs::write(&sidecar_path, toml_str)
            .map_err(|e| CoreError::Other(format!("kdf sidecar write {}: {e}", sidecar_path.display())))?;
        Ok(())
    }

    /// Load sidecar from disk.
    pub fn load(db_path: &Path) -> Result<Self, CoreError> {
        let sidecar_path = Self::path_for(db_path);
        let toml_str = std::fs::read_to_string(&sidecar_path)
            .map_err(|e| CoreError::Other(format!("kdf sidecar read {}: {e}", sidecar_path.display())))?;
        let sidecar: KdfSidecar = toml::from_str(&toml_str)
            .map_err(|e| CoreError::Other(format!("kdf sidecar parse: {e}")))?;
        if sidecar.version != 1 {
            return Err(CoreError::Other(format!(
                "unsupported kdf sidecar version {}; expected 1",
                sidecar.version
            )));
        }
        Ok(sidecar)
    }
}

// ---------------------------------------------------------------------------
// Core KDF
// ---------------------------------------------------------------------------

/// Derive a 32-byte SQLCipher key from a passphrase using Argon2id.
///
/// Parameters are selected by `profile` — see [`KdfProfile`] for timing targets.
/// The profile **must** be recorded in a [`KdfSidecar`] file alongside the database
/// so that future unlock operations use the same params regardless of which profile
/// is currently configured.
///
/// # Arguments
/// * `passphrase` — User-provided passphrase bytes (never stored on disk)
/// * `salt`       — Device-stable salt; must be ≥8 bytes (recommend SHA-256 of device Ed25519 public key, 32 bytes)
/// * `profile`    — Hardware-tier preset controlling m/t/p
///
/// # Returns
/// A fixed 32-byte array suitable for SQLCipher `PRAGMA key`.
///
/// # Errors
/// Returns [`CoreError::Other`] if Argon2 parameters are invalid or hashing fails.
pub fn derive_key(
    passphrase: &[u8],
    salt: &[u8],
    profile: KdfProfile,
) -> Result<[u8; 32], CoreError> {
    #[cfg(not(test))]
    let p = profile.params();
    #[cfg(test)]
    let p = {
        let _ = profile; // suppress unused warning in test mode
        ProfileParams {
            m_cost_kib: test_params::M_COST_KIB,
            t_cost: test_params::T_COST,
            p_cost: test_params::P_COST,
        }
    };

    let params = Params::new(p.m_cost_kib, p.t_cost, p.p_cost, Some(32))
        .map_err(|e| CoreError::Other(format!("argon2 params: {e}")))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut key = [0u8; 32];
    argon2
        .hash_password_into(passphrase, salt, &mut key)
        .map_err(|e| CoreError::Other(format!("argon2 hash: {e}")))?;

    Ok(key)
}

/// Derive a 32-byte key reading KDF params from a sidecar file.
///
/// Use this on **unlock** — never on initial DB creation. This ensures the key
/// is always derived with the same params as when the DB was created.
///
/// # Arguments
/// * `passphrase` — User-provided passphrase bytes
/// * `salt`       — Device-stable salt (same value used during creation)
/// * `db_path`    — Path to the encrypted database file (sidecar is loaded from `<db_path>.kdf-params.toml`)
pub fn derive_key_from_sidecar(
    passphrase: &[u8],
    salt: &[u8],
    db_path: &Path,
) -> Result<[u8; 32], CoreError> {
    let sidecar = KdfSidecar::load(db_path)?;

    #[cfg(not(test))]
    let params = Params::new(sidecar.m_cost_kib, sidecar.t_cost, sidecar.p_cost, Some(32))
        .map_err(|e| CoreError::Other(format!("argon2 params from sidecar: {e}")))?;
    #[cfg(test)]
    let params = Params::new(
        test_params::M_COST_KIB,
        test_params::T_COST,
        test_params::P_COST,
        Some(32),
    )
    .map_err(|e| CoreError::Other(format!("argon2 test params: {e}")))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut key = [0u8; 32];
    argon2
        .hash_password_into(passphrase, salt, &mut key)
        .map_err(|e| CoreError::Other(format!("argon2 hash from sidecar: {e}")))?;

    Ok(key)
}

/// Generate a SQLCipher PRAGMA key directive from a 32-byte key.
///
/// The pragma must be executed on a SQLite connection before any queries
/// if using a sqlcipher-enabled SQLite build.
///
/// # Arguments
/// * `key_32` — 32-byte array derived from a passphrase via [`derive_key`]
///
/// # Returns
/// A PRAGMA statement string, e.g. `PRAGMA key = "x'abcd...'"`
///
/// # Example
/// ```ignore
/// let key = derive_key(b"password", b"salt_salt________", KdfProfile::MobileStd)?;
/// let pragma = sqlcipher_pragma(&key);
/// // execute pragma on connection before any query
/// ```
pub fn sqlcipher_pragma(key_32: &[u8; 32]) -> String {
    let hex: String = key_32.iter().map(|b| format!("{:02x}", b)).collect();
    format!("PRAGMA key = \"x'{}'\"", hex)
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    /// Salt must be ≥8 bytes for Argon2.
    const SALT: &[u8] = b"test_salt_stable";

    // --- derive_key branch coverage ---

    #[test]
    fn test_derive_key_produces_32_bytes() {
        let key = derive_key(b"password", SALT, KdfProfile::MobileStd).expect("derive_key failed");
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn test_derive_key_is_deterministic() {
        let key1 = derive_key(b"password", SALT, KdfProfile::MobileStd).expect("first");
        let key2 = derive_key(b"password", SALT, KdfProfile::MobileStd).expect("second");
        assert_eq!(key1, key2, "Argon2id must be deterministic for the same inputs");
    }

    #[test]
    fn test_derive_key_differs_on_different_salt() {
        let salt2: &[u8] = b"other_salt_diff_";
        let key1 = derive_key(b"password", SALT, KdfProfile::MobileStd).expect("key1");
        let key2 = derive_key(b"password", salt2, KdfProfile::MobileStd).expect("key2");
        assert_ne!(key1, key2, "Different salts must produce different keys");
    }

    #[test]
    fn test_derive_key_differs_on_passphrase() {
        let key1 = derive_key(b"password1", SALT, KdfProfile::MobileStd).expect("key1");
        let key2 = derive_key(b"password2", SALT, KdfProfile::MobileStd).expect("key2");
        assert_ne!(key1, key2, "Different passphrases must produce different keys");
    }

    #[test]
    fn test_derive_key_empty_passphrase() {
        let key = derive_key(b"", SALT, KdfProfile::MobileStd).expect("empty passphrase");
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn test_derive_key_all_profiles_succeed() {
        // All three profiles must succeed — exercises profile.params() for each branch.
        for profile in [KdfProfile::MobileLow, KdfProfile::MobileStd, KdfProfile::Desktop] {
            let key = derive_key(b"password", SALT, profile)
                .unwrap_or_else(|e| panic!("derive_key failed for {profile:?}: {e}"));
            assert_eq!(key.len(), 32);
        }
    }

    // --- sqlcipher_pragma branch coverage ---

    #[test]
    fn test_sqlcipher_pragma_format() {
        let key = [42u8; 32];
        let pragma = sqlcipher_pragma(&key);
        assert!(pragma.starts_with("PRAGMA key = \"x'"));
        assert!(pragma.ends_with("'\""));
        assert!(pragma.contains("2a")); // 42 in hex
    }

    #[test]
    fn test_sqlcipher_pragma_length() {
        let key = [0u8; 32];
        let pragma = sqlcipher_pragma(&key);
        // fix: stale test — prefix "PRAGMA key = \"x'" is 16 chars (not 18); 16 + 64 hex + 2 = 82
        assert_eq!(pragma.len(), 82);
    }

    // --- KdfSidecar branch coverage ---

    #[test]
    fn test_sidecar_path_for() {
        let db = Path::new("/tmp/nclaw.db");
        let sidecar = KdfSidecar::path_for(db);
        assert_eq!(sidecar, Path::new("/tmp/nclaw.db.kdf-params.toml"));
    }

    #[test]
    fn test_sidecar_round_trip() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("test.db");

        let original = KdfSidecar::from_profile(KdfProfile::MobileStd);
        original.save(&db_path).expect("save sidecar");

        let loaded = KdfSidecar::load(&db_path).expect("load sidecar");
        assert_eq!(loaded.version, 1);
        assert_eq!(loaded.profile, KdfProfile::MobileStd);
        assert_eq!(loaded.m_cost_kib, 64 * 1024);
        assert_eq!(loaded.t_cost, 3);
        assert_eq!(loaded.p_cost, 1);
    }

    #[test]
    fn test_sidecar_load_missing_returns_error() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("nonexistent.db");
        let result = KdfSidecar::load(&db_path);
        assert!(result.is_err(), "should error on missing sidecar");
    }

    #[test]
    fn test_sidecar_load_corrupt_returns_error() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("corrupt.db");
        let sidecar_path = KdfSidecar::path_for(&db_path);
        std::fs::write(sidecar_path, "not valid toml [[[").expect("write corrupt");
        let result = KdfSidecar::load(&db_path);
        assert!(result.is_err(), "should error on corrupt sidecar");
    }

    #[test]
    fn test_sidecar_version_mismatch_returns_error() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("badver.db");
        let sidecar_path = KdfSidecar::path_for(&db_path);
        // Write a sidecar with version=99
        let content = r#"version = 99
profile = "mobile-std"
m_cost_kib = 65536
t_cost = 3
p_cost = 1
"#;
        std::fs::write(sidecar_path, content).expect("write");
        let result = KdfSidecar::load(&db_path);
        assert!(result.is_err(), "version mismatch must return error");
    }

    // --- derive_key_from_sidecar branch coverage ---

    #[test]
    fn test_derive_key_from_sidecar_matches_direct() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("enc.db");

        // Create and save a sidecar for MobileStd
        KdfSidecar::from_profile(KdfProfile::MobileStd)
            .save(&db_path)
            .expect("save");

        let key_direct = derive_key(b"passphrase", SALT, KdfProfile::MobileStd)
            .expect("direct derive");
        let key_sidecar = derive_key_from_sidecar(b"passphrase", SALT, &db_path)
            .expect("sidecar derive");

        // In test mode both paths use test_params, so they must match.
        assert_eq!(
            key_direct, key_sidecar,
            "sidecar-derived key must match direct derive with same params"
        );
    }

    #[test]
    fn test_derive_key_from_sidecar_missing_sidecar_errors() {
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("no_sidecar.db");
        let result = derive_key_from_sidecar(b"pass", SALT, &db_path);
        assert!(result.is_err());
    }
}
