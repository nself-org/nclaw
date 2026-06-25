//! XChaCha20-Poly1305 AEAD seal/open for E2EE transport.
//!
//! Purpose: Encrypt (seal) and decrypt (open) message payloads using
//!          XChaCha20-Poly1305 with per-call random 24-byte nonces via OsRng.
//!          Authentication tag is verified before any plaintext is returned —
//!          auth failure yields DecryptionFailed without partial plaintext.
//!
//! Inputs:  32-byte session key, plaintext/ciphertext bytes, AAD bytes.
//! Outputs: EncryptedMessage { nonce, ciphertext, aad } or E2EEError.
//! Constraints: Nonce is OsRng (never deterministic/counter). No oracle on failure.
//!              No key material in JSON-RPC error messages.
//! SPORT: REGISTRY-SERVICES.md — libnclaw-server status=implemented.

use chacha20poly1305::{
    aead::{Aead, KeyInit, OsRng},
    AeadCore, XChaCha20Poly1305, XNonce,
};
use serde::{Deserialize, Serialize};

use super::keys::E2EEError;

/// An encrypted message as returned by `seal` and consumed by `open`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedMessage {
    /// 24-byte random nonce (base64-encoded in JSON transport).
    #[serde(with = "serde_bytes_b64")]
    pub nonce: [u8; 24],
    /// Ciphertext + 16-byte Poly1305 authentication tag.
    #[serde(with = "serde_vec_b64")]
    pub ciphertext: Vec<u8>,
    /// Additional authenticated data (not encrypted, but authenticated).
    #[serde(with = "serde_vec_b64")]
    pub aad: Vec<u8>,
}

/// Encrypt `plaintext` with `key` and authenticate with `aad`.
///
/// Generates a fresh 24-byte nonce via OsRng on every call.
/// Returns an `EncryptedMessage` containing the nonce, ciphertext+tag, and aad.
pub fn seal(key: &[u8; 32], plaintext: &[u8], aad: &[u8]) -> Result<EncryptedMessage, E2EEError> {
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|_| E2EEError::EncryptionFailed)?;
    let nonce_generic = XChaCha20Poly1305::generate_nonce(&mut OsRng);
    let nonce: [u8; 24] = nonce_generic.into();

    let payload = chacha20poly1305::aead::Payload { msg: plaintext, aad };
    let ciphertext = cipher
        .encrypt(&XNonce::from(nonce), payload)
        .map_err(|_| E2EEError::EncryptionFailed)?;

    Ok(EncryptedMessage {
        nonce,
        ciphertext,
        aad: aad.to_vec(),
    })
}

/// Decrypt `msg` with `key`, verifying the Poly1305 authentication tag.
///
/// Returns plaintext only when the tag is valid. Any tampering with the
/// ciphertext, nonce, or AAD returns `DecryptionFailed` — no partial plaintext
/// is ever returned.
pub fn open(key: &[u8; 32], msg: &EncryptedMessage) -> Result<Vec<u8>, E2EEError> {
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|_| E2EEError::DecryptionFailed)?;
    let payload = chacha20poly1305::aead::Payload {
        msg: &msg.ciphertext,
        aad: &msg.aad,
    };
    cipher
        .decrypt(&XNonce::from(msg.nonce), payload)
        .map_err(|_| E2EEError::DecryptionFailed)
}

// ── Serde helpers for base64-encoded byte fields ───────────────────────────

mod serde_bytes_b64 {
    use base64::{engine::general_purpose::STANDARD, Engine};
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(bytes: &[u8; 24], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&STANDARD.encode(bytes))
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<[u8; 24], D::Error> {
        let b64 = String::deserialize(d)?;
        let v = STANDARD.decode(&b64).map_err(serde::de::Error::custom)?;
        v.try_into().map_err(|_| serde::de::Error::custom("expected 24 bytes"))
    }
}

mod serde_vec_b64 {
    use base64::{engine::general_purpose::STANDARD, Engine};
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(bytes: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&STANDARD.encode(bytes))
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let b64 = String::deserialize(d)?;
        STANDARD.decode(&b64).map_err(serde::de::Error::custom)
    }
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> [u8; 32] {
        [0x42u8; 32]
    }

    #[test]
    fn test_seal_open_roundtrip() {
        let key = test_key();
        let plaintext = b"hello nclaw e2ee world";
        let aad = b"session-id-123";
        let msg = seal(&key, plaintext, aad).expect("seal failed");
        let decrypted = open(&key, &msg).expect("open failed");
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_tampered_ciphertext_returns_decryption_failed() {
        let key = test_key();
        let mut msg = seal(&key, b"secret", b"aad").expect("seal failed");
        // Flip a byte in the ciphertext.
        if let Some(b) = msg.ciphertext.first_mut() {
            *b ^= 0xFF;
        }
        let result = open(&key, &msg);
        assert!(
            matches!(result, Err(E2EEError::DecryptionFailed)),
            "Tampered ciphertext must return DecryptionFailed, got {result:?}"
        );
    }

    #[test]
    fn test_tampered_nonce_returns_decryption_failed() {
        let key = test_key();
        let mut msg = seal(&key, b"secret", b"aad").expect("seal failed");
        msg.nonce[0] ^= 0xFF;
        let result = open(&key, &msg);
        assert!(matches!(result, Err(E2EEError::DecryptionFailed)));
    }

    #[test]
    fn test_tampered_aad_returns_decryption_failed() {
        let key = test_key();
        let mut msg = seal(&key, b"secret", b"aad-original").expect("seal failed");
        msg.aad = b"aad-tampered".to_vec();
        let result = open(&key, &msg);
        assert!(matches!(result, Err(E2EEError::DecryptionFailed)));
    }

    #[test]
    fn test_unique_nonces_per_call() {
        let key = test_key();
        let msg1 = seal(&key, b"a", b"").unwrap();
        let msg2 = seal(&key, b"a", b"").unwrap();
        assert_ne!(msg1.nonce, msg2.nonce, "Each seal call must use a fresh nonce");
    }

    #[test]
    fn test_wrong_key_returns_decryption_failed() {
        let key1 = test_key();
        let key2 = [0x99u8; 32];
        let msg = seal(&key1, b"secret", b"").unwrap();
        assert!(matches!(open(&key2, &msg), Err(E2EEError::DecryptionFailed)));
    }
}
