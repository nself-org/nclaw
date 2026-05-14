//! Client-side vault: Ed25519 keypair generation, XChaCha20-Poly1305 envelope encryption,
//! and OS keychain integration (macOS Keychain, Windows DPAPI, Linux Secret Service).

pub mod envelope;
pub mod keychain;
pub mod keypair;

#[cfg(feature = "vault")]
pub use envelope::Envelope;
pub use keypair::DeviceKeypair;
