//! Encryption-at-rest helpers for nClaw database.
//!
//! Mobile: SQLite + SQLCipher via passphrase-derived key (Argon2id 32-byte).
//! Desktop: pglite/embedded-postgres encrypts via OS disk encryption (FileVault, BitLocker, LUKS) — no app-level key needed.
//!
//! Full integration with SQLCipher lands in S16.T09b after sqlcipher crate audit.

use crate::error::CoreError;

/// Derive a 32-byte key from a user passphrase using Argon2id.
/// Salt should be device-stable (e.g., per-device pubkey hash).
///
/// # Arguments
/// * `passphrase` - User-provided passphrase bytes
/// * `salt` - Device-stable salt (recommend SHA256 of device public key)
///
/// # Returns
/// A fixed 32-byte array suitable for SQLCipher PRAGMA key.
///
/// # Note
/// This is a placeholder using hash-based derivation. Real Argon2id integration
/// lands in S16.T09b when sqlcipher bindings are finalized and audited.
pub fn derive_key(passphrase: &[u8], salt: &[u8]) -> Result<[u8; 32], CoreError> {
    // Placeholder: combine passphrase + salt via hasher.
    // Production: use argon2 crate with proper parameters.
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    passphrase.hash(&mut hasher);
    salt.hash(&mut hasher);
    let hash1 = hasher.finish();

    let mut hasher = DefaultHasher::new();
    hash1.hash(&mut hasher);
    let hash2 = hasher.finish();

    let mut key = [0u8; 32];
    for (i, byte) in hash1.to_le_bytes().iter().enumerate() {
        key[i] ^= byte;
    }
    for (i, byte) in hash2.to_be_bytes().iter().enumerate() {
        key[(i + 8) % 32] ^= byte;
    }

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
/// let key = derive_key(b"password", b"salt")?;
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

    #[test]
    fn test_derive_key_produces_32_bytes() {
        let key = derive_key(b"password", b"salt").expect("derive_key failed");
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn test_derive_key_is_deterministic() {
        let key1 = derive_key(b"password", b"salt").expect("first derive_key failed");
        let key2 = derive_key(b"password", b"salt").expect("second derive_key failed");
        assert_eq!(key1, key2);
    }

    #[test]
    fn test_derive_key_differs_on_passphrase() {
        let key1 = derive_key(b"password1", b"salt").expect("derive_key 1 failed");
        let key2 = derive_key(b"password2", b"salt").expect("derive_key 2 failed");
        assert_ne!(key1, key2);
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
