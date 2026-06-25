//! E2EE key generation and OS keychain storage.
//!
//! Purpose: Generate X25519 static keypairs, persist private key material
//!          exclusively in the OS keychain (never plaintext on disk), and
//!          derive a SHA-256 fingerprint from the public key.
//!
//! Inputs:  service name, key name, raw secret bytes.
//! Outputs: (StaticSecret, PublicKey), fingerprint hex string, E2EEError.
//! Constraints: Private key leaves this module only as a zeroized newtype.
//!              No logging of key material at any level.
//! SPORT: REGISTRY-SERVICES.md — libnclaw-server sidecar (keys module=implemented).

use keyring::Entry;
use sha2::{Digest, Sha256};
use thiserror::Error;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Service name used for all nclaw E2EE keychain entries.
pub const KEYCHAIN_SERVICE: &str = "com.nself.nclaw.e2ee";

/// Errors produced by E2EE key operations.
#[derive(Debug, Error)]
pub enum E2EEError {
    #[error("keychain read failed")]
    KeychainRead,
    #[error("keychain write failed")]
    KeychainWrite,
    #[error("invalid key length (expected 32 bytes)")]
    InvalidKeyLength,
    #[error("decryption failed")]
    DecryptionFailed,
    #[error("encryption failed")]
    EncryptionFailed,
    #[error("HKDF expand failed")]
    HkdfExpand,
}

/// Newtype wrapping `StaticSecret` with guaranteed zeroize-on-drop.
///
/// Purpose: Ensure private key bytes are wiped from memory when this value
///          is dropped, regardless of how the caller handles it.
pub struct KeychainSecret(pub StaticSecret);

impl Zeroize for KeychainSecret {
    fn zeroize(&mut self) {
        // x25519_dalek::StaticSecret implements Zeroize.
        self.0.zeroize();
    }
}

impl ZeroizeOnDrop for KeychainSecret {}

/// Generate a fresh X25519 keypair using the OS CSPRNG.
///
/// Returns `(KeychainSecret, PublicKey)`. The secret must be stored via
/// `save_to_keychain` before the process exits — it is NOT automatically persisted.
pub fn generate_keypair() -> (KeychainSecret, PublicKey) {
    let secret = StaticSecret::random_from_rng(rand_core::OsRng);
    let public = PublicKey::from(&secret);
    (KeychainSecret(secret), public)
}

/// Persist the raw 32-byte secret in the OS keychain.
///
/// Encoded as lowercase hex before storage so the keychain entry is a
/// human-inspectable string — the hex never appears in any log.
pub fn save_to_keychain(key_name: &str, secret_bytes: &[u8; 32]) -> Result<(), E2EEError> {
    let entry = Entry::new(KEYCHAIN_SERVICE, key_name).map_err(|_| E2EEError::KeychainWrite)?;
    let hex = hex_encode(secret_bytes);
    entry.set_password(&hex).map_err(|_| E2EEError::KeychainWrite)?;
    Ok(())
}

/// Load a static secret from the OS keychain, returning it as a `KeychainSecret`.
///
/// The hex string retrieved from the keychain is decoded, placed in a
/// `KeychainSecret`, and the intermediate hex buffer is zeroized immediately.
pub fn load_from_keychain(key_name: &str) -> Result<KeychainSecret, E2EEError> {
    let entry = Entry::new(KEYCHAIN_SERVICE, key_name).map_err(|_| E2EEError::KeychainRead)?;
    let mut hex = entry.get_password().map_err(|_| E2EEError::KeychainRead)?;
    let bytes = hex_decode(&hex).map_err(|_| E2EEError::InvalidKeyLength)?;
    // Zeroize the hex string from memory before it leaves this scope.
    hex.zeroize();
    let arr: [u8; 32] = bytes.try_into().map_err(|_| E2EEError::InvalidKeyLength)?;
    let secret = StaticSecret::from(arr);
    Ok(KeychainSecret(secret))
}

/// Derive a 64-character lowercase hex fingerprint from a public key.
///
/// SHA-256(public_key_bytes) → hex.  Used for key registry lookups.
pub fn fingerprint(pub_key: &PublicKey) -> String {
    let digest = Sha256::digest(pub_key.as_bytes());
    hex_encode(digest.as_slice())
}

// ── Internal hex helpers (no external dep to avoid version churn) ──────────

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn hex_decode(s: &str) -> Result<Vec<u8>, ()> {
    if s.len() % 2 != 0 {
        return Err(());
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| ()))
        .collect()
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_keypair_roundtrip() {
        let (secret, public) = generate_keypair();
        let derived = PublicKey::from(&secret.0);
        assert_eq!(derived.as_bytes(), public.as_bytes());
    }

    #[test]
    fn test_fingerprint_is_64_char_hex() {
        let (_, public) = generate_keypair();
        let fp = fingerprint(&public);
        assert_eq!(fp.len(), 64);
        assert!(fp.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_fingerprint_deterministic() {
        let (_, public) = generate_keypair();
        assert_eq!(fingerprint(&public), fingerprint(&public));
    }

    #[test]
    fn test_hex_encode_decode_roundtrip() {
        let bytes: [u8; 32] = [0xAB; 32];
        let hex = hex_encode(&bytes);
        let decoded = hex_decode(&hex).unwrap();
        assert_eq!(decoded, bytes.to_vec());
    }

    // Keychain round-trip test is integration-only (requires OS keychain).
    // Use NCLAW_TEST_KEYCHAIN=1 to enable locally.
    #[test]
    #[ignore = "requires OS keychain — run with NCLAW_TEST_KEYCHAIN=1"]
    fn test_keychain_roundtrip() {
        let (secret, _) = generate_keypair();
        let raw: [u8; 32] = secret.0.to_bytes();
        let key_name = "test-key-e9-roundtrip";
        save_to_keychain(key_name, &raw).expect("save failed");
        let loaded = load_from_keychain(key_name).expect("load failed");
        assert_eq!(loaded.0.to_bytes(), raw);
    }
}
