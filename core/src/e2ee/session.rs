//! ECDH + HKDF-SHA256 session key derivation for E2EE transport.
//!
//! Purpose: Given a local static/ephemeral X25519 secret and a remote public key,
//!          perform X25519 ECDH then expand the shared secret through HKDF-SHA256
//!          (using the `ring` crate) to produce a 32-byte session key.
//!
//! Inputs:  Local StaticSecret (consumed by value), remote PublicKey, HKDF info bytes.
//! Outputs: E2EESession { session_key: [u8; 32] }, zeroized on drop.
//! Constraints: StaticSecret is consumed by value so zeroize fires on ECDH completion.
//!              HKDF info must be b"nclaw-v1" (enforced by const).
//!              No session_key in any debug output.
//! SPORT: F08-SERVICE-INVENTORY.md — libnclaw in-process library.

pub use super::keys::E2EEError;
use ring::hkdf::{self, HKDF_SHA256};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// The canonical HKDF info string for nclaw E2EE session derivation.
pub const NCLAW_HKDF_INFO: &[u8] = b"nclaw-v1";

/// A derived session key, zeroized on drop.
///
/// Holds only the 32-byte output key material — no raw shared secret.
pub struct E2EESession {
    /// 32-byte session key derived via HKDF-SHA256.
    pub session_key: [u8; 32],
}

impl Zeroize for E2EESession {
    fn zeroize(&mut self) {
        self.session_key.zeroize();
    }
}

impl ZeroizeOnDrop for E2EESession {}

// Prevent session_key from appearing in debug output.
impl std::fmt::Debug for E2EESession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("E2EESession { session_key: [REDACTED] }")
    }
}

/// Derive a session key from an X25519 ECDH exchange and HKDF-SHA256 expansion.
///
/// Steps:
///   1. Perform X25519 ECDH (local_priv consumed — zeroize fires on shared secret drop).
///   2. Create an HKDF Salt with empty salt bytes (as per spec §3.3).
///   3. Extract PRK from the shared secret bytes.
///   4. Expand PRK with `info` into a 32-byte OKM → session_key.
///
/// The `info` parameter MUST be `NCLAW_HKDF_INFO` (`b"nclaw-v1"`) for
/// all production calls. The parameter is accepted for testability only.
pub fn derive_session(
    local_priv: StaticSecret,
    remote_pub: PublicKey,
    info: &[u8],
) -> Result<E2EESession, E2EEError> {
    // Step 1: X25519 ECDH. local_priv consumed here — its zeroize fires on drop.
    let shared_secret = local_priv.diffie_hellman(&remote_pub);

    // Step 2: HKDF-SHA256 with empty salt.
    let salt = hkdf::Salt::new(HKDF_SHA256, &[]);

    // Step 3: Extract PRK.
    let prk = salt.extract(shared_secret.as_bytes());

    // Step 4: Expand into 32 bytes.
    let mut okm = [0u8; 32];
    prk.expand(&[info], HKDF_SHA256)
        .map_err(|_| E2EEError::HkdfExpand)?
        .fill(&mut okm)
        .map_err(|_| E2EEError::HkdfExpand)?;

    Ok(E2EESession { session_key: okm })
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::e2ee::keys::generate_keypair;

    #[test]
    fn test_two_party_session_key_identical() {
        // Party A and B generate ephemeral keypairs, then each derives a session key
        // from their own secret + the other's public key. Both must arrive at the
        // same session_key.
        let (secret_a, pub_a) = generate_keypair();
        let (secret_b, pub_b) = generate_keypair();

        let session_a = derive_session(secret_a.0, pub_b, NCLAW_HKDF_INFO).expect("A failed");
        let session_b = derive_session(secret_b.0, pub_a, NCLAW_HKDF_INFO).expect("B failed");

        assert_eq!(
            session_a.session_key, session_b.session_key,
            "Both parties must derive identical session keys"
        );
    }

    #[test]
    fn test_session_key_is_32_bytes() {
        let (secret, _) = generate_keypair();
        let (_, remote_pub) = generate_keypair();
        let session = derive_session(secret.0, remote_pub, NCLAW_HKDF_INFO).unwrap();
        assert_eq!(session.session_key.len(), 32);
    }

    #[test]
    fn test_debug_does_not_expose_key() {
        let (secret, remote_pub) = generate_keypair();
        let session = derive_session(secret.0, remote_pub, NCLAW_HKDF_INFO).unwrap();
        let dbg = format!("{session:?}");
        assert!(
            dbg.contains("REDACTED"),
            "Debug must not expose session_key bytes"
        );
    }
}
