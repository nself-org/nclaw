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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::lww::{EventEnvelope, Op};

    fn make_test_event(user_id: uuid::Uuid) -> EventEnvelope {
        EventEnvelope {
            event_id: uuid::Uuid::nil(),
            entity_type: "TestEntity".to_string(),
            entity_id: uuid::Uuid::nil(),
            op: Op::Insert,
            timestamp: crate::sync::hlc::Hlc {
                wall_ms: 1000,
                lamport: 0,
                device_id: uuid::Uuid::nil(),
            },
            user_id,
            device_id: uuid::Uuid::nil(),
            tenant_id: None,
            payload: Some(serde_json::json!({"name": "test"})),
            schema_version: 1,
            signature: vec![],
        }
    }

    #[test]
    fn signing_material_is_deterministic() {
        let uid = uuid::Uuid::nil();
        let ev1 = make_test_event(uid);
        let ev2 = make_test_event(uid);
        let material1 = signing_material(&ev1, uid);
        let material2 = signing_material(&ev2, uid);
        assert_eq!(material1, material2);
        assert!(!material1.is_empty());
    }

    /// V04-F02 / V04-F05 core defense: different user_ids MUST produce
    /// different signing material so a signature valid for user A is
    /// provably invalid under user B's identity.
    #[test]
    fn signing_material_changes_with_different_user_id() {
        let uid_a = uuid::Uuid::nil();
        let uid_b = uuid::Uuid::from_bytes([1u8; 16]);
        let ev = make_test_event(uid_a);
        let material_a = signing_material(&ev, uid_a);
        let material_b = signing_material(&ev, uid_b);
        assert_ne!(material_a, material_b);
    }

    #[test]
    fn signing_material_changes_with_different_op() {
        let uid = uuid::Uuid::nil();
        let mut ev1 = make_test_event(uid);
        let mut ev2 = make_test_event(uid);
        ev1.op = Op::Insert;
        ev2.op = Op::Delete;

        let material1 = signing_material(&ev1, uid);
        let material2 = signing_material(&ev2, uid);
        assert_ne!(material1, material2);
    }

    #[test]
    fn signing_material_changes_with_different_event_id() {
        let uid = uuid::Uuid::nil();
        let mut ev1 = make_test_event(uid);
        let mut ev2 = make_test_event(uid);
        ev1.event_id = uuid::Uuid::from_bytes([2u8; 16]);
        ev2.event_id = uuid::Uuid::from_bytes([3u8; 16]);

        let material1 = signing_material(&ev1, uid);
        let material2 = signing_material(&ev2, uid);
        assert_ne!(material1, material2);
    }

    #[test]
    fn signing_material_without_vault_feature_compiles() {
        let uid = uuid::Uuid::nil();
        let ev = make_test_event(uid);
        let _material = signing_material(&ev, uid);
    }

    /// V04-F05 golden fixture: locks the byte layout against the Go server.
    /// Inputs match `tests/fixtures/cross_lang_sign_golden.json`; the bytes
    /// here must equal `canonicalSigningMaterial(...)` in
    /// `plugins-pro/paid/nself-sync/cmd/nself-sync/main.go` for the same
    /// envelope.
    ///
    /// Inputs:
    ///   user_id     = 11111111-1111-1111-1111-111111111111
    ///   event_id    = 22222222-2222-2222-2222-222222222222
    ///   entity_type = "Note"
    ///   entity_id   = 33333333-3333-3333-3333-333333333333
    ///   op          = Insert (0)
    ///   wall_ms     = 1_715_626_800_000
    ///   lamport     = 17
    ///   hlc_device_id = device_id = 44444444-4444-4444-4444-444444444444
    ///   tenant_id   = None
    ///   schema_ver  = 1
    ///   payload     = {"k":"v"}  (canonical — no whitespace, sorted keys)
    #[test]
    fn signing_material_golden_fixture_v04_f05() {
        let user_id = uuid::Uuid::parse_str("11111111-1111-1111-1111-111111111111").unwrap();
        let event_id = uuid::Uuid::parse_str("22222222-2222-2222-2222-222222222222").unwrap();
        let entity_id = uuid::Uuid::parse_str("33333333-3333-3333-3333-333333333333").unwrap();
        let device_id = uuid::Uuid::parse_str("44444444-4444-4444-4444-444444444444").unwrap();

        let env = EventEnvelope {
            event_id,
            entity_type: "Note".to_string(),
            entity_id,
            op: Op::Insert,
            timestamp: crate::sync::hlc::Hlc {
                wall_ms: 1_715_626_800_000,
                lamport: 17,
                device_id,
            },
            user_id,
            device_id,
            tenant_id: None,
            payload: Some(serde_json::json!({"k": "v"})),
            schema_version: 1,
            signature: vec![],
        };

        let material = signing_material(&env, user_id);

        let mut expected = Vec::new();
        expected.extend_from_slice(event_id.as_bytes()); // 16
        expected.extend_from_slice(&4_i32.to_le_bytes()); // 4
        expected.extend_from_slice(b"Note"); // 4
        expected.extend_from_slice(entity_id.as_bytes()); // 16
        expected.push(0u8); // 1 — op Insert
        expected.extend_from_slice(&1_715_626_800_000_i64.to_le_bytes()); // 8
        expected.extend_from_slice(&17_u64.to_le_bytes()); // 8 — u64 LE == i64 LE for non-negative
        expected.extend_from_slice(device_id.as_bytes()); // 16 — hlc_device_id
        expected.extend_from_slice(user_id.as_bytes()); // 16
        expected.extend_from_slice(device_id.as_bytes()); // 16 — device_id
        expected.push(0u8); // 1 — tenant absent
        expected.extend_from_slice(&1_i32.to_le_bytes()); // 4 — schema_version
        expected.extend_from_slice(br#"{"k":"v"}"#); // 9 — canonical payload

        assert_eq!(material, expected, "byte layout drift from Go server");
        // 16+4+4+16+1+8+8+16+16+16+1+4+9 = 119 bytes
        assert_eq!(material.len(), 119, "expected 119-byte signing material");
    }

    #[test]
    fn signing_material_changes_with_tenant_id() {
        let uid = uuid::Uuid::nil();
        let mut ev_no_tenant = make_test_event(uid);
        ev_no_tenant.tenant_id = None;
        let mut ev_with_tenant = make_test_event(uid);
        ev_with_tenant.tenant_id = Some(uuid::Uuid::from_bytes([7u8; 16]));

        let m1 = signing_material(&ev_no_tenant, uid);
        let m2 = signing_material(&ev_with_tenant, uid);
        assert_ne!(m1, m2, "tenant flag must affect signing material");
    }

    #[test]
    fn signing_material_changes_with_schema_version() {
        let uid = uuid::Uuid::nil();
        let mut ev1 = make_test_event(uid);
        ev1.schema_version = 1;
        let mut ev2 = make_test_event(uid);
        ev2.schema_version = 2;

        let m1 = signing_material(&ev1, uid);
        let m2 = signing_material(&ev2, uid);
        assert_ne!(m1, m2, "schema_version must affect signing material");
    }
}
