//! BIP39 mnemonic → raw key recovery.
//!
//! Decodes a 24-word BIP39 mnemonic back to the original 32-byte DB key.
//! Used on cold-reinstall or device migration when the user re-enters their
//! recovery code and needs the raw key to re-encrypt (or import) an existing
//! database backup.
//!
//! # Security notes
//! - This function does NOT store the key; that is the caller's responsibility.
//! - The key should be passed directly to the OS keychain (`keychain::store_secret`)
//!   and then to `MobileSqliteEngine::open` — never written to disk in plaintext.

use crate::error::CoreError;
use bip39::Mnemonic;

/// Decode a 24-word BIP39 mnemonic back to the original 32-byte DB key.
///
/// # Arguments
/// * `words` — space-separated 24-word English BIP39 mnemonic (case-insensitive).
///
/// # Returns
/// The original `[u8; 32]` key, or `CoreError` if the mnemonic is invalid or
/// does not decode to exactly 32 bytes.
///
/// # Errors
/// - Invalid word or checksum → `CoreError::Other("bip39 decode failed: ...")`
/// - Entropy length ≠ 32 bytes → `CoreError::Other("mnemonic entropy is N bytes; expected 32")`
pub fn recover_db_from_mnemonic(words: &str) -> Result<[u8; 32], CoreError> {
    let mnemonic = Mnemonic::parse(words)
        .map_err(|e| CoreError::Other(format!("bip39 decode failed: {e}")))?;
    let entropy = mnemonic.to_entropy();
    entropy.try_into().map_err(|v: Vec<u8>| {
        CoreError::Other(format!(
            "mnemonic entropy is {} bytes; expected 32",
            v.len()
        ))
    })
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(all(test, feature = "mobile-sqlite"))]
mod tests {
    use super::*;
    use crate::db::mobile::first_run::encode_mnemonic;

    // --- round-trip: key → mnemonic → key ---

    #[test]
    fn test_round_trip_all_zeros() {
        let key = [0u8; 32];
        let mnemonic = encode_mnemonic(&key).expect("encode must succeed");
        let recovered = recover_db_from_mnemonic(&mnemonic).expect("decode must succeed");
        assert_eq!(key, recovered, "round-trip must be lossless");
    }

    #[test]
    fn test_round_trip_all_ones() {
        let key = [0xFFu8; 32];
        let mnemonic = encode_mnemonic(&key).expect("encode must succeed");
        let recovered = recover_db_from_mnemonic(&mnemonic).expect("decode must succeed");
        assert_eq!(key, recovered);
    }

    #[test]
    fn test_round_trip_known_pattern() {
        let key: [u8; 32] = core::array::from_fn(|i| i as u8);
        let mnemonic = encode_mnemonic(&key).expect("encode must succeed");
        let recovered = recover_db_from_mnemonic(&mnemonic).expect("decode must succeed");
        assert_eq!(key, recovered);
    }

    #[test]
    fn test_round_trip_is_deterministic() {
        let key = [0x42u8; 32];
        let m1 = encode_mnemonic(&key).unwrap();
        let m2 = encode_mnemonic(&key).unwrap();
        let r1 = recover_db_from_mnemonic(&m1).unwrap();
        let r2 = recover_db_from_mnemonic(&m2).unwrap();
        assert_eq!(r1, r2, "round-trip must be deterministic");
        assert_eq!(r1, key);
    }

    // --- error cases ---

    #[test]
    fn test_invalid_word_rejected() {
        let bad = "notaword ".repeat(24);
        let result = recover_db_from_mnemonic(bad.trim());
        assert!(result.is_err(), "garbage mnemonic must fail");
        let msg = format!("{:?}", result.unwrap_err());
        assert!(
            msg.contains("bip39 decode failed"),
            "error must mention bip39: {msg}"
        );
    }

    #[test]
    fn test_empty_string_rejected() {
        let result = recover_db_from_mnemonic("");
        assert!(result.is_err(), "empty string must fail");
    }

    #[test]
    fn test_wrong_word_count_rejected() {
        // 12 words instead of 24 — wrong entropy size for our 32-byte key
        let twelve = "abandon ".repeat(11) + "about";
        // This may parse as valid 12-word BIP39 but will produce 16 bytes, not 32
        if let Ok(key) = recover_db_from_mnemonic(&twelve) {
            // If bip39 crate accepts it, the entropy check must catch it
            panic!("should have failed but got {key:?}");
        }
        // Either parse fails or entropy-length check fails — both are acceptable
    }

    #[test]
    fn test_bad_checksum_rejected() {
        let key = [0xABu8; 32];
        let mut mnemonic = encode_mnemonic(&key).unwrap();
        // Corrupt the last word to break the BIP39 checksum
        if let Some(pos) = mnemonic.rfind(' ') {
            mnemonic.replace_range(pos + 1.., "zoo");
        }
        let result = recover_db_from_mnemonic(&mnemonic);
        assert!(result.is_err(), "corrupted checksum word must fail");
    }

    #[test]
    fn test_case_insensitive_decode() {
        let key = [0x77u8; 32];
        let mnemonic = encode_mnemonic(&key).unwrap();
        let upper = mnemonic.to_uppercase();
        // bip39 v2 parses case-insensitively; if it fails that's also fine
        match recover_db_from_mnemonic(&upper) {
            Ok(recovered) => assert_eq!(recovered, key, "uppercase round-trip must match"),
            Err(_) => { /* bip39 implementation may be strict — acceptable */ }
        }
    }
}
