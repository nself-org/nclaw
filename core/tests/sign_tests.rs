//! Integration tests for libnclaw::sync::sign — signing material layout and cross-language
//! byte-identity against the Go server's `canonicalSigningMaterial`.
//!
//! Golden fixture: tests/fixtures/cross_lang_sign_golden.json
//! Go counterpart: plugins-pro/paid/nself-sync/cmd/nself-sync/push_test.go::TestSigningMaterial_CrossLanguage

use libnclaw::sync::hlc::Hlc;
use libnclaw::sync::lww::{EventEnvelope, Op};
use libnclaw::sync::sign::signing_material;

fn make_test_event(user_id: uuid::Uuid) -> EventEnvelope {
    EventEnvelope {
        event_id: uuid::Uuid::nil(),
        entity_type: "TestEntity".to_string(),
        entity_id: uuid::Uuid::nil(),
        op: Op::Insert,
        timestamp: Hlc {
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
/// `plugins-pro/paid/nself-sync/cmd/nself-sync/main.go` for the same envelope.
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
        timestamp: Hlc {
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
    expected.extend_from_slice(&17_u64.to_le_bytes()); // 8
    expected.extend_from_slice(device_id.as_bytes()); // 16 — hlc_device_id
    expected.extend_from_slice(user_id.as_bytes()); // 16
    expected.extend_from_slice(device_id.as_bytes()); // 16 — device_id
    expected.push(0u8); // 1 — tenant absent
    expected.extend_from_slice(&1_i32.to_le_bytes()); // 4 — schema_version
    expected.extend_from_slice(br#"{"k":"v"}"#); // 9 — canonical payload

    assert_eq!(material, expected, "byte layout drift from Go server");
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
