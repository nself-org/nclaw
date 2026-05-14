//! Client-side vault: Ed25519 keypair generation, XChaCha20-Poly1305 envelope encryption,
//! and OS keychain integration (macOS Keychain, Windows DPAPI, Linux Secret Service).

pub mod envelope;
pub mod keychain;
pub mod keypair;
pub mod registration;
pub mod sync;
pub mod revocation;
pub mod rotation;
pub mod telemetry;

pub use envelope::Envelope;
pub use keypair::DeviceKeypair;
pub use registration::{DeviceRegistration, DeviceRegistered, register};
pub use sync::{VaultEnvelope, fetch_envelopes};
pub use revocation::revoke;
pub use rotation::{RotationCadence, next_rotation_at, should_rotate_now};
pub use telemetry::{VaultTelemetry, VaultTelemetrySnapshot};
