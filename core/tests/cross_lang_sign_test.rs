//! Cross-language signing-material golden test (P102 W11 V04-F05).
//!
//! Loads `tests/fixtures/cross_lang_sign_golden.json` and verifies the Rust
//! `signing_material()` implementation in `nclaw/core/src/sync/sign.rs`
//! produces the byte-identical canonical material that the Go server's
//! `canonicalSigningMaterial()` in
//! `plugins-pro/paid/nself-sync/cmd/nself-sync/main.go` produces for the
//! same envelope.
//!
//! Drift between the two languages → every Rust-signed event is rejected
//! by the live Go server with "invalid signature". This test is the
//! locked guardrail that prevents that class of regression.
//!
//! Paired Go test: `plugins-pro/paid/nself-sync/cmd/nself-sync/push_test.go`
//! `TestSigningMaterial_CrossLanguage`.

use libnclaw::sync::hlc::Hlc;
use libnclaw::sync::lww::{EventEnvelope, Op};
use libnclaw::sync::sign::signing_material;
use serde_json::Value;
use std::path::PathBuf;

fn fixture_path() -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("tests");
    p.push("fixtures");
    p.push("cross_lang_sign_golden.json");
    p
}

fn load_fixture() -> Value {
    let bytes = std::fs::read(fixture_path()).expect("read cross_lang_sign_golden.json");
    serde_json::from_slice(&bytes).expect("parse cross_lang_sign_golden.json")
}

fn parse_uuid(s: &str) -> uuid::Uuid {
    uuid::Uuid::parse_str(s).expect("parse uuid")
}

fn parse_op(s: &str) -> Op {
    match s {
        "insert" => Op::Insert,
        "update" => Op::Update,
        "delete" => Op::Delete,
        other => panic!("unknown op: {other}"),
    }
}

fn fixture_envelope(fixture: &Value) -> (EventEnvelope, uuid::Uuid) {
    let env = &fixture["envelope"];
    let user_id = parse_uuid(env["user_id"].as_str().unwrap());
    let envelope = EventEnvelope {
        event_id: parse_uuid(env["event_id"].as_str().unwrap()),
        entity_type: env["entity_type"].as_str().unwrap().to_string(),
        entity_id: parse_uuid(env["entity_id"].as_str().unwrap()),
        op: parse_op(env["op"].as_str().unwrap()),
        timestamp: Hlc {
            wall_ms: env["hlc_wall_ms"].as_i64().unwrap(),
            lamport: env["hlc_lamport"].as_u64().unwrap(),
            device_id: parse_uuid(env["hlc_device_id"].as_str().unwrap()),
        },
        user_id,
        device_id: parse_uuid(env["device_id"].as_str().unwrap()),
        tenant_id: env
            .get("tenant_id")
            .and_then(|v| v.as_str())
            .map(parse_uuid),
        payload: Some(env["payload"].clone()),
        schema_version: env["schema_version"].as_u64().unwrap() as u32,
        signature: vec![],
    };
    (envelope, user_id)
}

#[test]
fn cross_lang_signing_material_matches_go_golden_bytes() {
    let fixture = load_fixture();
    let expected_hex = fixture["expected_material_hex"].as_str().expect("expected_material_hex");
    let expected_len = fixture["expected_length"].as_u64().expect("expected_length") as usize;
    let expected_bytes = hex_decode(expected_hex);

    let (env, user_id) = fixture_envelope(&fixture);
    let material = signing_material(&env, user_id);

    assert_eq!(
        material.len(),
        expected_len,
        "cross-language signing material length drift — Go and Rust must agree"
    );
    assert_eq!(
        material, expected_bytes,
        "cross-language signing material bytes drift — Go and Rust MUST produce byte-identical output"
    );
}

#[test]
fn cross_lang_payload_tail_is_canonical_json() {
    let fixture = load_fixture();
    let canon_hex = fixture["expected_payload_canonical_hex"]
        .as_str()
        .expect("expected_payload_canonical_hex");
    let canon_bytes = hex_decode(canon_hex);

    let (env, user_id) = fixture_envelope(&fixture);
    let material = signing_material(&env, user_id);

    let tail = &material[material.len() - canon_bytes.len()..];
    assert_eq!(tail, canon_bytes.as_slice(),
        "payload tail must be RFC-8785 canonical JSON, byte-identical to Go's canonicalJSON output");
}

/// Decode a contiguous hex string (no whitespace, no `0x` prefix) into bytes.
/// Lower- and upper-case hex digits are both accepted.
fn hex_decode(s: &str) -> Vec<u8> {
    assert!(s.len() % 2 == 0, "hex string length must be even");
    let mut out = Vec::with_capacity(s.len() / 2);
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let hi = hex_nibble(bytes[i]);
        let lo = hex_nibble(bytes[i + 1]);
        out.push((hi << 4) | lo);
        i += 2;
    }
    out
}

fn hex_nibble(b: u8) -> u8 {
    match b {
        b'0'..=b'9' => b - b'0',
        b'a'..=b'f' => b - b'a' + 10,
        b'A'..=b'F' => b - b'A' + 10,
        other => panic!("non-hex character: {other:?}"),
    }
}
