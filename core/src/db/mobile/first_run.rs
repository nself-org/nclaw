//! First-run database key generation and keychain storage.
//!
//! On first launch (no DB file present at the expected path), this module:
//!
//! 1. Generates 32 cryptographically random bytes via `getrandom`.
//! 2. Stores them in the OS keychain under `service="org.nself.nclaw", account="db-key"`.
//! 3. Emits the raw key bytes to the caller for use as a SQLCipher passphrase.
//! 4. Returns the BIP39 mnemonic (24 words for 256-bit entropy) so the caller can
//!    display the recovery code once to the user.
//!
//! On subsequent launches the key is loaded from the keychain — no regeneration.
//!
//! # Security notes
//! - The raw key is never persisted to disk (keychain only).
//! - The BIP39 mnemonic is NEVER stored; the caller is responsible for showing it to
//!   the user exactly once and discarding it.
//! - On Linux CI (no Secret Service daemon), set `NCLAW_SKIP_KEYCHAIN=1` to skip
//!   keychain tests. The `fetch_or_generate_db_key` function will still compile and
//!   error at runtime if the Secret Service is unavailable — this is a noted risk
//!   for headless Linux environments (ESCALATE_TO_ARCH tracking: Linux keyring daemon
//!   as a CI pre-requisite).

use crate::error::CoreError;
use crate::vault::keychain;
use bip39::Mnemonic;
use std::path::Path;

/// Keychain account identifier for the mobile DB key.
pub const DB_KEY_ACCOUNT: &str = "db-key";

/// Result of `fetch_or_generate_db_key`.
pub struct DbKeyResult {
    /// 32-byte database key. Pass this directly to `MobileSqliteEngine::open`.
    pub key: [u8; 32],
    /// Present only on first run. A 24-word BIP39 mnemonic encoding the key.
    /// Display to the user exactly once; do NOT store it anywhere.
    /// On subsequent launches this is `None`.
    pub recovery_mnemonic: Option<String>,
}

/// Fetch the DB key from the keychain, or generate it on first run.
///
/// # First run (DB file absent at `db_path`)
/// 1. Generate 32 random bytes via `getrandom`.
/// 2. Store in keychain under `DB_KEY_ACCOUNT`.
/// 3. Encode as 24-word BIP39 mnemonic and return it in `recovery_mnemonic`.
///
/// # Subsequent runs (DB file present)
/// Load the key from keychain. `recovery_mnemonic` is `None`.
///
/// # Errors
/// Returns `CoreError` if random generation fails, keychain access fails, or the
/// stored key is not 32 bytes (corrupt keychain entry).
///
/// # Linux headless CI risk
/// `keyring` uses the freedesktop Secret Service on Linux. In a headless CI container
/// without a running Secret Service daemon (e.g. GNOME Keyring), `keyring::Entry::new`
/// will return a `NoStorageAccess` error. Set `NCLAW_SKIP_KEYCHAIN=1` to skip the
/// keychain-touching tests in that environment. This does NOT affect iOS or Android targets.
pub fn fetch_or_generate_db_key(db_path: &Path) -> Result<DbKeyResult, CoreError> {
    if db_path.exists() {
        // Subsequent launch — load from keychain.
        let raw = keychain::fetch_secret(DB_KEY_ACCOUNT)?;
        let key = key_from_vec(raw)?;
        return Ok(DbKeyResult {
            key,
            recovery_mnemonic: None,
        });
    }

    // First run — generate, store, encode.
    let key = generate_random_key()?;
    keychain::store_secret(DB_KEY_ACCOUNT, &key)?;
    let mnemonic = encode_mnemonic(&key)?;
    Ok(DbKeyResult {
        key,
        recovery_mnemonic: Some(mnemonic),
    })
}

/// Generate 32 cryptographically random bytes using `getrandom`.
///
/// Errors if the OS CSPRNG is unavailable (should not happen in production).
fn generate_random_key() -> Result<[u8; 32], CoreError> {
    let mut key = [0u8; 32];
    getrandom::getrandom(&mut key)
        .map_err(|e| CoreError::Other(format!("getrandom failed: {e}")))?;
    Ok(key)
}

/// Encode 32 bytes as a BIP39 24-word mnemonic (English wordlist, 256-bit entropy).
///
/// Returns the space-separated mnemonic string.
/// `pub(crate)` so the `recovery` module's tests can use it for round-trip verification.
pub(crate) fn encode_mnemonic(key: &[u8; 32]) -> Result<String, CoreError> {
    // BIP39 Mnemonic::from_entropy requires exactly 32 bytes for 24 words.
    let mnemonic = Mnemonic::from_entropy(key)
        .map_err(|e| CoreError::Other(format!("bip39 encode failed: {e}")))?;
    Ok(mnemonic.to_string())
}

/// Convert a `Vec<u8>` read from keychain into a fixed `[u8; 32]`.
fn key_from_vec(raw: Vec<u8>) -> Result<[u8; 32], CoreError> {
    raw.try_into().map_err(|v: Vec<u8>| {
        CoreError::Other(format!(
            "keychain db-key is {} bytes; expected 32 — entry may be corrupt",
            v.len()
        ))
    })
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    /// Skip keychain-touching tests in headless CI (Linux Secret Service unavailable).
    fn skip_keychain() -> bool {
        std::env::var("NCLAW_SKIP_KEYCHAIN").is_ok()
    }

    // --- generate_random_key ---

    #[test]
    fn test_generate_random_key_produces_32_bytes() {
        let key = generate_random_key().expect("getrandom must succeed on CI");
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn test_generate_random_key_is_non_deterministic() {
        // Two calls should (astronomically likely) differ.
        let k1 = generate_random_key().unwrap();
        let k2 = generate_random_key().unwrap();
        assert_ne!(k1, k2, "Two random 32-byte keys should differ");
    }

    // --- encode_mnemonic ---

    #[test]
    fn test_encode_mnemonic_produces_24_words() {
        let key = [0xABu8; 32];
        let mnemonic = encode_mnemonic(&key).expect("encode must succeed");
        let word_count = mnemonic.split_whitespace().count();
        assert_eq!(word_count, 24, "256-bit entropy must yield 24 BIP39 words");
    }

    #[test]
    fn test_encode_mnemonic_is_deterministic() {
        let key = [0x55u8; 32];
        let m1 = encode_mnemonic(&key).unwrap();
        let m2 = encode_mnemonic(&key).unwrap();
        assert_eq!(m1, m2, "Same key must always produce same mnemonic");
    }

    // --- key_from_vec ---

    #[test]
    fn test_key_from_vec_accepts_32_bytes() {
        let v: Vec<u8> = (0u8..32).collect();
        let key = key_from_vec(v.clone()).expect("32 bytes must convert");
        assert_eq!(&key[..], &v[..]);
    }

    #[test]
    fn test_key_from_vec_rejects_wrong_length() {
        let too_short: Vec<u8> = vec![0u8; 16];
        assert!(key_from_vec(too_short).is_err(), "16 bytes must fail");

        let too_long: Vec<u8> = vec![0u8; 64];
        assert!(key_from_vec(too_long).is_err(), "64 bytes must fail");
    }

    // --- fetch_or_generate_db_key (mock keychain via NCLAW_SKIP_KEYCHAIN) ---

    #[test]
    fn test_first_run_generates_mnemonic_and_stores_key() {
        if skip_keychain() {
            return;
        }
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("nclaw_test.db");

        // DB does not exist yet → first run path.
        let result = fetch_or_generate_db_key(&db_path).expect("first run must succeed");

        assert_eq!(result.key.len(), 32);
        let mnemonic = result
            .recovery_mnemonic
            .expect("first run must return mnemonic");
        assert_eq!(mnemonic.split_whitespace().count(), 24);

        // Cleanup keychain entry.
        let _ = keychain::delete_secret(DB_KEY_ACCOUNT);
    }

    #[test]
    fn test_subsequent_run_returns_no_mnemonic() {
        if skip_keychain() {
            return;
        }
        let dir = tempdir().expect("tempdir");
        let db_path = dir.path().join("nclaw_test2.db");

        // First run stores the key.
        let first = fetch_or_generate_db_key(&db_path).expect("first run");
        // Create a DB file to simulate the first run having completed.
        std::fs::write(&db_path, b"fake_db_content").expect("write fake db");

        // Second run: DB file exists → load from keychain.
        let second = fetch_or_generate_db_key(&db_path).expect("second run");

        assert_eq!(first.key, second.key, "key must be stable across runs");
        assert!(
            second.recovery_mnemonic.is_none(),
            "subsequent run must not return mnemonic"
        );

        let _ = keychain::delete_secret(DB_KEY_ACCOUNT);
    }
}
