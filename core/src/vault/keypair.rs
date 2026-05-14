//! Ed25519 device keypair generation, storage, and verification.
//!
//! Provides a persistent per-device Ed25519 keypair for client authentication
//! and message signing. Keys are generated once and stored in the OS keychain.

use crate::error::{CoreError, VaultError};
use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use rand::rngs::OsRng;

/// Represents a device's Ed25519 signing keypair.
pub struct DeviceKeypair {
    pub signing_key: SigningKey,
}

impl DeviceKeypair {
    /// Generate a new Ed25519 keypair using the OS random number generator.
    pub fn generate() -> Self {
        let mut csprng = OsRng;
        let signing_key = SigningKey::generate(&mut csprng);
        Self { signing_key }
    }

    /// Reconstruct a keypair from its 32-byte secret key.
    pub fn from_bytes(bytes: &[u8; 32]) -> Result<Self, CoreError> {
        let signing_key = SigningKey::from_bytes(bytes);
        Ok(Self { signing_key })
    }

    /// Export the signing key as a 32-byte array.
    pub fn to_bytes(&self) -> [u8; 32] {
        self.signing_key.to_bytes()
    }

    /// Export the public key as a 32-byte array.
    pub fn public_bytes(&self) -> [u8; 32] {
        self.signing_key.verifying_key().to_bytes()
    }

    /// Sign a message and return the signature.
    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        self.signing_key.sign(message).to_bytes().to_vec()
    }
}

/// Verify a message signature using a public key (32 bytes).
pub fn verify(pubkey: &[u8; 32], message: &[u8], signature: &[u8]) -> Result<(), CoreError> {
    let vk = VerifyingKey::from_bytes(pubkey).map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!(
            "public key invalid: {}",
            e
        )))
    })?;
    let sig = ed25519_dalek::Signature::from_slice(signature).map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!(
            "signature invalid: {}",
            e
        )))
    })?;
    vk.verify_strict(message, &sig).map_err(|_| {
        CoreError::Vault(VaultError::DecryptionFailed(
            "signature verification failed".into(),
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keypair_generate_and_export() {
        let keypair = DeviceKeypair::generate();
        let pubkey = keypair.public_bytes();
        let privkey = keypair.to_bytes();

        assert_eq!(pubkey.len(), 32);
        assert_eq!(privkey.len(), 32);
        assert_ne!(pubkey, [0u8; 32]);
        assert_ne!(privkey, [0u8; 32]);
    }

    #[test]
    fn test_keypair_from_bytes() {
        let kp1 = DeviceKeypair::generate();
        let bytes = kp1.to_bytes();
        let kp2 = DeviceKeypair::from_bytes(&bytes).unwrap();

        assert_eq!(kp1.to_bytes(), kp2.to_bytes());
        assert_eq!(kp1.public_bytes(), kp2.public_bytes());
    }

    #[test]
    fn test_sign_and_verify() {
        let keypair = DeviceKeypair::generate();
        let message = b"test message";

        let signature = keypair.sign(message);
        let pubkey = keypair.public_bytes();

        verify(&pubkey, message, &signature).expect("signature should verify");
    }

    #[test]
    fn test_verify_fails_for_tampered_message() {
        let keypair = DeviceKeypair::generate();
        let message = b"test message";
        let signature = keypair.sign(message);
        let pubkey = keypair.public_bytes();

        let tampered = b"tampered message";
        let result = verify(&pubkey, tampered, &signature);

        assert!(result.is_err());
    }

    #[test]
    fn test_verify_fails_for_tampered_signature() {
        let keypair = DeviceKeypair::generate();
        let message = b"test message";
        let mut signature = keypair.sign(message);
        let pubkey = keypair.public_bytes();

        if !signature.is_empty() {
            signature[0] ^= 1; // flip a bit
        }

        let result = verify(&pubkey, message, &signature);
        assert!(result.is_err());
    }
}
