//! Event signing and verification using Ed25519 from vault keypair.
//!
//! Provides deterministic signing material generation and verification
//! of event envelopes using the device's Ed25519 keypair.
//!
//! ## P102 W11 hotfix (V04-F05, 2026-05-14)
//!
//! The signing material now byte-matches the **authoritative** Go server
//! function `canonicalSigningMaterial` in
//! `plugins-pro/paid/nself-sync/cmd/nself-sync/main.go`. Prior layouts
//! produced by `sign.rs` (V04-F02) and `internal/auth/sig.go` were
//! INCONSISTENT with `main.go::canonicalSigningMaterial`, so every event
//! signed by the Rust client was being rejected by the live server with
//! `"invalid signature"`. This file is the converged client-side layout.
//!
//! Layout (concatenated, no separators; little-endian for ints):
//!
//!   event_id      16 bytes (UUID)
//!   entity_type   i32 LE length (4 bytes) || UTF-8 bytes
//!   entity_id     16 bytes (UUID)
//!   op byte       1 byte (0=insert, 1=update, 2=delete)
//!   hlc_wall_ms   i64 LE (8 bytes)
//!   hlc_lamport   i64 LE (8 bytes) — Rust u64 ↔ Go int64 are byte-identical for
//!                                   non-negative values; lamport never overflows
//!                                   i64 in practice (would require ≥ 2^63 events).
//!   hlc_device_id 16 bytes (UUID)
//!   user_id       16 bytes (UUID) — V04-F02: binds author identity into bytes
//!   device_id     16 bytes (UUID) — operation device (= hlc_device_id at the
//!                                   server boundary); kept distinct in the
//!                                   layout to allow future divergence.
//!   tenant_flag   1 byte (0=absent, 1=present)
//!   tenant_id     16 bytes UUID (only when tenant_flag==1)
//!   schema_ver    i32 LE (4 bytes)
//!   payload       RFC 8785 canonical JSON bytes (omitted if payload absent)
//!
//! `user_id` MUST be the authenticated identity from the auth context at
//! sign time, and MUST match `env.user_id`. Callers pass `user_id`
//! explicitly rather than reading it from the envelope so a tampered
//! envelope cannot choose its own signing identity.
//!
//! Cross-language golden fixtures live at:
//!   * Rust: `nclaw/core/tests/fixtures/cross_lang_sign_golden.json`
//!   * Rust: `nclaw/core/tests/cross_lang_sign_test.rs`
//!   * Go:   `plugins-pro/paid/nself-sync/cmd/nself-sync/push_test.go::TestSigningMaterial_CrossLanguage`

use crate::error::CoreError;
use crate::sync::canonical::canonical_json;
use crate::sync::lww::EventEnvelope;

/// Generate canonical signing material for an event envelope.
///
/// Output is byte-identical to Go's `canonicalSigningMaterial` in
/// `plugins-pro/paid/nself-sync/cmd/nself-sync/main.go`. See module docs for
/// the full layout. Locked by `cross_lang_sign_golden.json` and exercised by
/// matched Rust/Go tests on every CI run.
///
/// `user_id` is the JWT-authenticated identity; pass `env.user_id` for normal
/// signing, or a different value during cross-user-replay tests.
pub fn signing_material(env: &EventEnvelope, user_id: uuid::Uuid) -> Vec<u8> {
    let mut buf = Vec::with_capacity(256);

    // event_id (16 bytes UUID)
    buf.extend_from_slice(env.event_id.as_bytes());

    // entity_type — i32 LE length prefix, then UTF-8 bytes
    let et = env.entity_type.as_bytes();
    buf.extend_from_slice(&(et.len() as i32).to_le_bytes());
    buf.extend_from_slice(et);

    // entity_id (16 bytes UUID)
    buf.extend_from_slice(env.entity_id.as_bytes());

    // op byte (0=insert, 1=update, 2=delete)
    let op_byte: u8 = match env.op {
        crate::sync::lww::Op::Insert => 0,
        crate::sync::lww::Op::Update => 1,
        crate::sync::lww::Op::Delete => 2,
    };
    buf.push(op_byte);

    // hlc_wall_ms (i64 LE)
    buf.extend_from_slice(&env.timestamp.wall_ms.to_le_bytes());

    // hlc_lamport — Rust u64 LE bytes are byte-identical to Go int64 LE bytes for
    // any non-negative value (≤ 2^63 - 1). Lamport values are monotonic positive
    // counters; an overflow into the int64-negative range would require
    // 9.2 × 10^18 events, far outside any plausible deployment.
    buf.extend_from_slice(&env.timestamp.lamport.to_le_bytes());

    // hlc_device_id (16 bytes UUID)
    buf.extend_from_slice(env.timestamp.device_id.as_bytes());

    // user_id (16 bytes UUID) — V04-F02 identity binding
    buf.extend_from_slice(user_id.as_bytes());

    // device_id (16 bytes UUID) — operation device. Go's server binds this to
    // `ev.HLCDeviceID` (the JWT-claimed device must equal the HLC author
    // device). We emit `env.device_id` directly here; the caller is responsible
    // for ensuring `env.device_id == env.timestamp.device_id` (asserted by
    // `sign()` below).
    buf.extend_from_slice(env.device_id.as_bytes());

    // tenant_flag + optional tenant_id
    match env.tenant_id {
        Some(tid) => {
            buf.push(1);
            buf.extend_from_slice(tid.as_bytes());
        }
        None => {
            buf.push(0);
        }
    }

    // schema_version (i32 LE)
    buf.extend_from_slice(&(env.schema_version as i32).to_le_bytes());

    // payload — canonical JSON when present, omitted entirely otherwise
    if let Some(p) = &env.payload {
        buf.extend_from_slice(&canonical_json(p));
    }

    buf
}

/// Sign an event envelope using the device keypair.
///
/// Only available when the "vault" feature is enabled.
/// Fills the event's `signature` field with the Ed25519 signature.
///
/// `user_id` is the authenticated identity at sign time. The function
/// asserts that `user_id == env.user_id`; mismatch yields an error rather
/// than silently signing a forged identity binding.
///
/// Also asserts `env.device_id == env.timestamp.device_id` so the device_id
/// portion of the signing material lines up with what the Go server rebuilds
/// (`canonicalSigningMaterial` writes `ev.HLCDeviceID` twice — once as
/// hlc_device_id and once as device_id). A mismatch here would produce
/// bytes the server cannot reconstruct.
#[cfg(feature = "vault")]
pub fn sign(
    env: &mut EventEnvelope,
    user_id: uuid::Uuid,
    keypair: &crate::vault::keypair::DeviceKeypair,
) -> Result<(), CoreError> {
    if env.user_id != user_id {
        return Err(CoreError::Other(
            "sign: env.user_id does not match authenticated user_id".into(),
        ));
    }
    if env.device_id != env.timestamp.device_id {
        return Err(CoreError::Other(
            "sign: env.device_id must equal env.timestamp.device_id".into(),
        ));
    }
    let material = signing_material(env, user_id);
    env.signature = keypair.sign(&material);
    Ok(())
}

/// Verify an event envelope's signature using a public key.
///
/// Only available when the "vault" feature is enabled.
/// Returns an error if the signature is invalid or verification fails.
///
/// `user_id` is the asserted author identity for which the envelope was
/// signed. Pass the envelope's `user_id` for a straight verification; pass
/// a *different* `user_id` to detect cross-user replay attempts (the
/// signature will fail to verify).
#[cfg(feature = "vault")]
pub fn verify(
    env: &EventEnvelope,
    user_id: uuid::Uuid,
    pubkey: &[u8; 32],
) -> Result<(), CoreError> {
    let material = signing_material(env, user_id);
    crate::vault::keypair::verify(pubkey, &material, &env.signature)
}

/// Stub implementation when vault feature is disabled.
#[cfg(not(feature = "vault"))]
pub fn sign(
    _env: &mut EventEnvelope,
    _user_id: uuid::Uuid,
    _keypair: &(),
) -> Result<(), CoreError> {
    Err(CoreError::Other("vault feature not enabled".into()))
}

// Tests live in `tests/sign_tests.rs` (uses only public API).
