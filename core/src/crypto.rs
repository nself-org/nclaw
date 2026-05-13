//! End-to-end encryption for nClaw.
//!
//! Key exchange: X25519 ephemeral ECDH
//! Encryption:   ChaCha20-Poly1305 AEAD
//! Encoding:     base64 (standard alphabet, no padding)
//!
//! ## Wire format
//!
//! An encrypted message is:
//!   `<base64(nonce)>.<base64(ciphertext+tag)>`
//!
//! Both parts are standard base64. The dot separator allows
//! simple `split('.')` parsing on all client platforms.

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use chacha20poly1305::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    ChaCha20Poly1305, Key, Nonce,
};
use thiserror::Error;
use x25519_dalek::{EphemeralSecret, PublicKey, SharedSecret, StaticSecret};

/// Errors produced by crypto operations.
#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("base64 decode failed: {0}")]
    Base64(#[from] base64::DecodeError),

    #[error("invalid public key length (expected 32 bytes)")]
    InvalidPublicKey,

    #[error("encryption failed")]
    EncryptionFailed,

    #[error("decryption failed — message may be tampered")]
    DecryptionFailed,

    #[error("invalid wire format — expected '<nonce>.<ciphertext>'")]
    InvalidWireFormat,
}

// =============================================================================
// Key generation
// =============================================================================

/// A device's long-term static X25519 keypair.
pub struct DeviceKeypair {
    pub secret: StaticSecret,
    pub public: PublicKey,
}

impl DeviceKeypair {
    /// Generate a new random keypair.
    pub fn generate() -> Self {
        let secret = StaticSecret::random_from_rng(OsRng);
        let public = PublicKey::from(&secret);
        Self { secret, public }
    }

    /// Encode the public key as standard base64.
    pub fn public_key_b64(&self) -> String {
        B64.encode(self.public.as_bytes())
    }

    /// Decode a base64-encoded remote public key.
    pub fn decode_public_key(b64: &str) -> Result<PublicKey, CryptoError> {
        let bytes = B64.decode(b64)?;
        let arr: [u8; 32] = bytes.try_into().map_err(|_| CryptoError::InvalidPublicKey)?;
        Ok(PublicKey::from(arr))
    }

    /// Perform X25519 ECDH with a remote public key.
    /// Returns a `SessionCipher` ready for encryption.
    pub fn diffie_hellman(&self, remote_public_b64: &str) -> Result<SessionCipher, CryptoError> {
        let remote = Self::decode_public_key(remote_public_b64)?;
        let shared: SharedSecret = self.secret.diffie_hellman(&remote);
        Ok(SessionCipher::from_shared_secret(shared))
    }
}

/// An ephemeral keypair for a single pairing exchange.
/// Provides forward secrecy: the secret is consumed on first use.
pub struct EphemeralKeypair {
    pub secret: EphemeralSecret,
    pub public: PublicKey,
}

impl EphemeralKeypair {
    pub fn generate() -> Self {
        let secret = EphemeralSecret::random_from_rng(OsRng);
        let public = PublicKey::from(&secret);
        Self { secret, public }
    }

    pub fn public_key_b64(&self) -> String {
        B64.encode(self.public.as_bytes())
    }

    /// Consume the ephemeral secret in a DH exchange.
    pub fn diffie_hellman(
        self,
        remote_public_b64: &str,
    ) -> Result<SessionCipher, CryptoError> {
        let remote = DeviceKeypair::decode_public_key(remote_public_b64)?;
        let shared: SharedSecret = self.secret.diffie_hellman(&remote);
        Ok(SessionCipher::from_shared_secret(shared))
    }
}

// =============================================================================
// Session cipher (ChaCha20-Poly1305)
// =============================================================================

/// A symmetric cipher derived from a completed DH exchange.
/// Thread-safe: `encrypt`/`decrypt` take `&self`.
pub struct SessionCipher {
    cipher: ChaCha20Poly1305,
}

impl SessionCipher {
    fn from_shared_secret(shared: SharedSecret) -> Self {
        // Use the raw 32-byte shared secret directly as the ChaCha20 key.
        // X25519 output is already uniformly random — no KDF needed for this protocol.
        let key = Key::from_slice(shared.as_bytes());
        Self {
            cipher: ChaCha20Poly1305::new(key),
        }
    }

    /// Encrypt `plaintext` and return a dot-separated wire string.
    ///
    /// Format: `<base64(nonce)>.<base64(ciphertext+tag)>`
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<String, CryptoError> {
        let nonce = ChaCha20Poly1305::generate_nonce(&mut OsRng);
        let ciphertext = self
            .cipher
            .encrypt(&nonce, plaintext)
            .map_err(|_| CryptoError::EncryptionFailed)?;

        let wire = format!(
            "{}.{}",
            B64.encode(nonce.as_slice()),
            B64.encode(&ciphertext)
        );
        Ok(wire)
    }

    /// Decrypt a dot-separated wire string and return the plaintext.
    pub fn decrypt(&self, wire: &str) -> Result<Vec<u8>, CryptoError> {
        let (nonce_b64, ct_b64) = wire
            .split_once('.')
            .ok_or(CryptoError::InvalidWireFormat)?;

        let nonce_bytes = B64.decode(nonce_b64)?;
        let ct_bytes = B64.decode(ct_b64)?;

        let nonce = Nonce::from_slice(&nonce_bytes);
        let plaintext = self
            .cipher
            .decrypt(nonce, ct_bytes.as_slice())
            .map_err(|_| CryptoError::DecryptionFailed)?;

        Ok(plaintext)
    }

    /// Convenience: encrypt a UTF-8 string.
    pub fn encrypt_str(&self, plaintext: &str) -> Result<String, CryptoError> {
        self.encrypt(plaintext.as_bytes())
    }

    /// Convenience: decrypt and interpret as UTF-8.
    pub fn decrypt_str(&self, wire: &str) -> Result<String, CryptoError> {
        let bytes = self.decrypt(wire)?;
        String::from_utf8(bytes).map_err(|_| CryptoError::DecryptionFailed)
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_static_keypair() {
        let alice = DeviceKeypair::generate();
        let bob = DeviceKeypair::generate();

        let alice_cipher = alice.diffie_hellman(&bob.public_key_b64()).unwrap();
        let bob_cipher = bob.diffie_hellman(&alice.public_key_b64()).unwrap();

        let plaintext = "hello nClaw E2E";
        let wire = alice_cipher.encrypt_str(plaintext).unwrap();
        let decoded = bob_cipher.decrypt_str(&wire).unwrap();

        assert_eq!(decoded, plaintext);
    }

    #[test]
    fn roundtrip_ephemeral_keypair() {
        let server = DeviceKeypair::generate();
        let client = EphemeralKeypair::generate();
        let client_pub = client.public_key_b64();

        let client_cipher = client.diffie_hellman(&server.public_key_b64()).unwrap();
        let server_cipher = server.diffie_hellman(&client_pub).unwrap();

        let wire = client_cipher.encrypt_str("ephemeral test").unwrap();
        let decoded = server_cipher.decrypt_str(&wire).unwrap();
        assert_eq!(decoded, "ephemeral test");
    }

    #[test]
    fn tampered_ciphertext_fails() {
        let alice = DeviceKeypair::generate();
        let bob = DeviceKeypair::generate();

        let alice_cipher = alice.diffie_hellman(&bob.public_key_b64()).unwrap();
        let bob_cipher = bob.diffie_hellman(&alice.public_key_b64()).unwrap();

        let wire = alice_cipher.encrypt_str("secret").unwrap();
        // Flip the last byte of the ciphertext
        let mut tampered = wire.clone();
        let last = tampered.pop().unwrap();
        let replacement = if last == 'A' { 'B' } else { 'A' };
        tampered.push(replacement);

        assert!(bob_cipher.decrypt_str(&tampered).is_err());
    }
}
