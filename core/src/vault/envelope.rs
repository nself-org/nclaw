//! XChaCha20-Poly1305 envelope encryption for client-side secret storage.
//!
//! Provides high-level envelope API for sealing and opening secrets with authenticated
//! encryption. Feature-gated: the `vault` feature must be enabled at compile time.

use crate::error::{CoreError, VaultError};

/// Encrypted envelope containing ciphertext + nonce.
#[cfg(feature = "vault")]
pub struct Envelope {
    pub ciphertext: Vec<u8>,
    pub nonce: Vec<u8>,
}

#[cfg(feature = "vault")]
use chacha20poly1305::{aead::Aead, AeadCore, KeyInit, XChaCha20Poly1305};

/// Seal plaintext into an encrypted envelope using a 32-byte key.
///
/// Returns an Envelope containing the ciphertext and nonce.
/// Only available when the `vault` feature is enabled.
#[cfg(feature = "vault")]
pub fn seal(key_32: &[u8; 32], plaintext: &[u8]) -> Result<Envelope, CoreError> {
    let cipher = XChaCha20Poly1305::new(key_32.into());
    let nonce = XChaCha20Poly1305::generate_nonce(rand::rngs::OsRng);
    let ciphertext = cipher.encrypt(&nonce, plaintext).map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!("seal failed: {}", e)))
    })?;
    Ok(Envelope {
        ciphertext,
        nonce: nonce.to_vec(),
    })
}

/// Open an encrypted envelope using a 32-byte key.
///
/// Returns the plaintext on success. Fails if the ciphertext is tampered with
/// or the nonce is invalid.
/// Only available when the `vault` feature is enabled.
#[cfg(feature = "vault")]
pub fn open(key_32: &[u8; 32], envelope: &Envelope) -> Result<Vec<u8>, CoreError> {
    use chacha20poly1305::XNonce;

    let cipher = XChaCha20Poly1305::new(key_32.into());
    let nonce: &XNonce = (&envelope.nonce[..])
        .try_into()
        .map_err(|_| CoreError::Vault(VaultError::DecryptionFailed("nonce wrong size".into())))?;
    cipher
        .decrypt(nonce, envelope.ciphertext.as_ref())
        .map_err(|e| CoreError::Vault(VaultError::DecryptionFailed(format!("open failed: {}", e))))
}

/// Stub implementations when vault feature is not enabled.
#[cfg(not(feature = "vault"))]
pub fn seal(_key_32: &[u8; 32], _plaintext: &[u8]) -> Result<(), CoreError> {
    Err(CoreError::Vault(VaultError::EncryptionFailed(
        "vault feature not enabled at compile time".into(),
    )))
}

#[cfg(not(feature = "vault"))]
pub fn open(_key_32: &[u8; 32], _envelope: &()) -> Result<Vec<u8>, CoreError> {
    Err(CoreError::Vault(VaultError::DecryptionFailed(
        "vault feature not enabled at compile time".into(),
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(feature = "vault")]
    fn test_seal_and_open_roundtrip() {
        let key = &[42u8; 32];
        let plaintext = b"secret message";

        let envelope = seal(key, plaintext).expect("seal should succeed");
        assert!(!envelope.ciphertext.is_empty());
        assert_eq!(envelope.nonce.len(), 24); // XChaCha20 nonce is 24 bytes

        let decrypted = open(key, &envelope).expect("open should succeed");
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    #[cfg(feature = "vault")]
    fn test_seal_with_empty_plaintext() {
        let key = &[42u8; 32];
        let plaintext = b"";

        let envelope = seal(key, plaintext).expect("seal should succeed");
        let decrypted = open(key, &envelope).expect("open should succeed");
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    #[cfg(feature = "vault")]
    fn test_open_with_wrong_key() {
        let key1 = &[42u8; 32];
        let key2 = &[43u8; 32];
        let plaintext = b"secret message";

        let envelope = seal(key1, plaintext).expect("seal should succeed");
        let result = open(key2, &envelope);

        assert!(result.is_err());
    }

    #[test]
    #[cfg(feature = "vault")]
    fn test_open_with_tampered_ciphertext() {
        let key = &[42u8; 32];
        let plaintext = b"secret message";

        let mut envelope = seal(key, plaintext).expect("seal should succeed");
        if !envelope.ciphertext.is_empty() {
            envelope.ciphertext[0] ^= 1; // flip a bit
        }

        let result = open(key, &envelope);
        assert!(result.is_err());
    }

    #[test]
    #[cfg(not(feature = "vault"))]
    fn test_no_vault_feature_error() {
        let key = &[42u8; 32];
        let plaintext = b"secret";

        let result = seal(key, plaintext);
        assert!(result.is_err());
    }
}
