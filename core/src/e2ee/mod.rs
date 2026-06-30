//! E2EE submodule — transport-layer end-to-end encryption for nClaw.
//!
//! Purpose: X25519 key management, ECDH+HKDF-SHA256 session derivation,
//!          and XChaCha20-Poly1305 AEAD seal/open for the intelligence gRPC
//!          transport layer. Implements the OD-3 sidecar model: libnclaw-server
//!          exposes these operations over a Unix socket as JSON-RPC.
//!
//! Modules:
//!   - keys   — X25519 keypair generation and OS keychain storage
//!   - session — ECDH + HKDF-SHA256 session key derivation
//!   - codec  — XChaCha20-Poly1305 seal/open + EncryptedMessage type
//!
//! SPORT: REGISTRY-SERVICES.md — libnclaw-server sidecar.

pub mod codec;
pub mod keys;
pub mod session;

pub use codec::{open, seal, EncryptedMessage};
pub use keys::{
    fingerprint, generate_keypair, load_from_keychain, save_to_keychain, E2EEError, KeychainSecret,
};
pub use session::{derive_session, E2EESession, NCLAW_HKDF_INFO};
