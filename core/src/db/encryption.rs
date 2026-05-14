//! Encryption-at-rest helpers for nClaw database.
//!
//! Mobile: SQLite + SQLCipher via passphrase-derived key (Argon2id 32-byte).
//! Desktop: pglite/embedded-postgres encrypts via OS disk encryption (FileVault, BitLocker, LUKS) — no app-level key needed.
//!
//! Full integration with SQLCipher lands in S16.T09b after sqlcipher crate audit.

use crate::error::CoreError;
use argon2::{Algorithm, Argon2, Params, Version};

/// Derive a 32-byte key from a user passphrase using Argon2id.
///
/// Parameters (OWASP minimum for interactive logins, tuned to run in <1 s
/// on a modern mobile CPU while still being brute-force resistant):
/// - m = 64 MiB memory cost
/// - t = 3 iterations
/// - p = 1 parallelism
/// - output = 32 bytes
///
/// Salt should be device-stable (e.g., SHA-256 of the device's Ed25519 public key).
///
/// # Arguments
/// * `passphrase` - User-provided passphrase bytes
/// * `salt` - Device-stable salt (recommend SHA256 of device public key); must be ≥8 bytes
///
/// # Returns
/// A fixed 32-byte array suitable for SQLCipher PRAGMA key.
///
/// # Errors
/// Returns `CoreError::Other` if Argon2 parameters are invalid or hashing fails.
pub fn derive_key(passphrase: &[u8], salt: &[u8]) -> Result<[u8; 32], CoreError> {
    let params = Params::new(
        64 * 1024, // m_cost: 64 MiB
        3,         // t_cost: 3 iterations
        1,         // p_cost: 1 lane
        Some(32),  // output length: 32 bytes
    )
    .map_err(|e| CoreError::Other(format!("argon2 params: {e}")))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut key = [0u8; 32];
    argon2
        .hash_password_into(passphrase, salt, &mut key)
        .map_err(|e| CoreError::Other(format!("argon2 hash: {e}")))?;

    Ok(key)
}

/// Generate a SQLCipher PRAGMA key directive from a 32-byte key.
/// The pragma must be executed on a SQLite connection before any queries
/// if using a sqlcipher-enabled SQLite build.
///
/// # Arguments
/// * `key_32` - 32-byte array derived from a passphrase
///
/// # Returns
/// A PRAGMA statement as a string (e.g., `PRAGMA key = "x'...'"`).
///
/// # Example
/// ```ignore
/// let key = derive_key(b"password", b"salt_salt")?;
/// let pragma = sqlcipher_pragma(&key);
/// // pragma = "PRAGMA key = \"x'abcd...'\"";
/// ```
pub fn sqlcipher_pragma(key_32: &[u8; 32]) -> String {
    let hex: String = key_32.iter().map(|b| format!("{:02x}", b)).collect();
    format!("PRAGMA key = \"x'{}'\"", hex)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Salt must be ≥8 bytes for Argon2.
    const SALT: &[u8] = b"test_salt_stable";

    #[test]
    fn test_derive_key_produces_32_bytes() {
        let key = derive_key(b"password", SALT).expect("derive_key failed");
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn test_derive_key_is_deterministic() {
        // Same passphrase + same salt → identical key (H2: Argon2id is deterministic).
        let key1 = derive_key(b"password", SALT).expect("first derive_key failed");
        let key2 = derive_key(b"password", SALT).expect("second derive_key failed");
        assert_eq!(
            key1, key2,
            "Argon2id must be deterministic for the same inputs"
        );
    }

    #[test]
    fn test_derive_key_differs_on_different_salt() {
        // Different salt → different key (H2: salt isolation).
        let salt2: &[u8] = b"other_salt_diff_";
        let key1 = derive_key(b"password", SALT).expect("derive_key 1 failed");
        let key2 = derive_key(b"password", salt2).expect("derive_key 2 failed");
        assert_ne!(key1, key2, "Different salts must produce different keys");
    }

    #[test]
    fn test_derive_key_differs_on_passphrase() {
        // Different passphrase → different key.
        let key1 = derive_key(b"password1", SALT).expect("derive_key 1 failed");
        let key2 = derive_key(b"password2", SALT).expect("derive_key 2 failed");
        assert_ne!(
            key1, key2,
            "Different passphrases must produce different keys"
        );
    }

    #[test]
    fn test_derive_key_empty_passphrase() {
        // Empty passphrase is unusual but must not panic — still produces a 32-byte key.
        let key = derive_key(b"", SALT).expect("derive_key with empty passphrase failed");
        assert_eq!(key.len(), 32);
    }

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
        // "PRAGMA key = \"x'" (18) + 64 hex chars + "'\"" (2) = 84
        assert_eq!(pragma.len(), 84);
    }
}
