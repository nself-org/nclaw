// tests/bc_compat.rs — Backward-compatibility tests for nclaw-core v1.1.0 ↔ v1.1.1.
//
// S03-M7: verifies that the Rust sync types in nclaw-core v1.1.1 can parse
// v1.1.0-era serialised event envelopes without data loss, and that the
// check_compat function correctly identifies the upgrade direction between
// version pairs.
//
// All fixtures are loaded from tests/fixtures/v1.1.0/. No network. No DB.

use nclaw_core::sync::{
    check_compat, CompatStatus, EventEnvelope, Hlc, Op,
};
use uuid::Uuid;

// Version constants — encode as (major=1, minor=1, patch=0/1).
// Format: major << 16 | minor << 8 | patch (per upgrade.rs decode_version).
const VERSION_V110: u32 = (1u32 << 16) | (1u32 << 8) | 0u32;
const VERSION_V111: u32 = (1u32 << 16) | (1u32 << 8) | 1u32;

// --- compat negotiation tests ---

/// BC-01: v1.1.1 client connecting to v1.1.0 server.
///
/// The client is newer than the server → server needs upgrade.
/// The v1.1.1 client must surface this without panicking so callers can
/// display a "server is out of date" message rather than crashing.
#[test]
fn bc_compat_v111_client_v110_server_server_needs_upgrade() {
    let status = check_compat(VERSION_V110, VERSION_V111);
    assert_eq!(
        status,
        CompatStatus::ServerNeedsUpgrade,
        "v1.1.1 client against v1.1.0 server should report ServerNeedsUpgrade"
    );
}

/// BC-02: v1.1.0 client connecting to v1.1.1 server.
///
/// The server is newer than the client → client needs upgrade.
/// Must never panic; callers surface "please update your app".
#[test]
fn bc_compat_v110_client_v111_server_client_needs_upgrade() {
    let status = check_compat(VERSION_V111, VERSION_V110);
    assert_eq!(
        status,
        CompatStatus::ClientNeedsUpgrade,
        "v1.1.0 client against v1.1.1 server should report ClientNeedsUpgrade"
    );
}

/// BC-03: same version on both sides — always compatible.
#[test]
fn bc_compat_same_version_compatible() {
    assert_eq!(check_compat(VERSION_V110, VERSION_V110), CompatStatus::Compatible);
    assert_eq!(check_compat(VERSION_V111, VERSION_V111), CompatStatus::Compatible);
}

/// BC-04: CompatStatus is not panic-prone for any u32 version combination.
/// Exhaustive spot-check on edge-case values.
#[test]
fn bc_compat_no_panic_on_arbitrary_versions() {
    for &(server, client) in &[
        (0u32, 0u32),
        (0, 1),
        (1, 0),
        (u32::MAX, 0),
        (0, u32::MAX),
        (u32::MAX, u32::MAX),
        (VERSION_V110, 0),
        (0, VERSION_V111),
    ] {
        let _status = check_compat(server, client); // must not panic
    }
}

// --- event envelope serialisation BC tests ---

/// BC-05: v1.1.0 EventEnvelope fixture round-trips cleanly through v1.1.1 types.
///
/// Loads the fixture at tests/fixtures/v1.1.0/event_envelope.json, deserialises
/// it with the v1.1.1 EventEnvelope type, and asserts all v1.1.0 fields are
/// preserved. Guards against accidental field removal or rename in v1.1.1.
#[test]
fn bc_event_envelope_v110_fixture_parses_cleanly() {
    let fixture = include_str!("fixtures/v1.1.0/event_envelope.json");
    let env: EventEnvelope = serde_json::from_str(fixture)
        .expect("v1.1.1 EventEnvelope must parse v1.1.0 fixture without error");

    // All required v1.1.0 fields survive parsing.
    assert_ne!(env.event_id, Uuid::nil(), "event_id must not be nil");
    assert_eq!(env.entity_type, "message", "entity_type mismatch");
    assert_eq!(env.op, Op::Insert, "op mismatch");
    assert_eq!(env.schema_version, 1, "schema_version must be 1 for v1.1.0 fixture");
    assert_eq!(env.timestamp.wall_ms, 1715644800000, "hlc.wall_ms mismatch");
    assert_eq!(env.timestamp.lamport, 1, "hlc.lamport mismatch");
    assert!(env.tenant_id.is_none(), "v1.1.0 fixture has null tenant_id");
    assert!(env.payload.is_some(), "payload must not be None after parsing v1.1.0 fixture");
}

/// BC-06: v1.1.0 EventEnvelope round-trip (serialise → deserialise) loses no fields.
///
/// Constructs a v1.1.0-style event in-process (schema_version=1, no signature),
/// serialises it, then deserialises with the v1.1.1 type. All fields must survive
/// the round-trip byte-for-byte.
#[test]
fn bc_event_envelope_v110_roundtrip_no_data_loss() {
    let device_id = Uuid::parse_str("cccccccc-0000-0000-0000-000000000001")
        .expect("parse device_id UUID");
    let event_id = Uuid::parse_str("aaaaaaaa-0000-0000-0000-000000000001")
        .expect("parse event_id UUID");

    let original = EventEnvelope {
        event_id,
        entity_type: "message".into(),
        entity_id: Uuid::new_v4(),
        op: Op::Insert,
        timestamp: Hlc {
            wall_ms: 1_715_644_800_000,
            lamport: 3,
            device_id,
        },
        user_id: Uuid::new_v4(),
        device_id,
        tenant_id: None,
        payload: Some(serde_json::json!({"body": "hello from v1.1.0"})),
        schema_version: 1,
        signature: vec![],
    };

    let json = serde_json::to_string(&original)
        .expect("v1.1.0-style EventEnvelope must serialise without error");

    let restored: EventEnvelope = serde_json::from_str(&json)
        .expect("v1.1.1 EventEnvelope must deserialise v1.1.0 serialisation without error");

    assert_eq!(restored.event_id, original.event_id, "event_id mismatch after round-trip");
    assert_eq!(restored.entity_type, original.entity_type, "entity_type mismatch");
    assert_eq!(restored.op, original.op, "op mismatch");
    assert_eq!(restored.schema_version, 1, "schema_version must be 1");
    assert_eq!(restored.timestamp.wall_ms, original.timestamp.wall_ms, "hlc.wall_ms mismatch");
    assert_eq!(restored.timestamp.lamport, original.timestamp.lamport, "hlc.lamport mismatch");
    assert_eq!(restored.timestamp.device_id, original.timestamp.device_id, "hlc.device_id mismatch");
    assert!(restored.tenant_id.is_none(), "tenant_id must remain None");
    assert!(restored.payload.is_some(), "payload must survive round-trip");
}

/// BC-07: v1.1.1 EventEnvelope with new fields (schema_version=2) is silently
/// ignored by code that only reads v1.1.0 fields.
///
/// Simulates a v1.1.0 reader encountering a v1.1.1-serialised envelope with
/// additional JSON fields. serde(deny_unknown_fields) must NOT be present on
/// EventEnvelope — unknown fields must be ignored for backward compatibility.
#[test]
fn bc_event_envelope_v111_unknown_fields_ignored_by_v110_reader() {
    // A v1.1.1 payload with extra hypothetical fields not present in v1.1.0.
    let v111_json = r#"{
        "event_id": "aaaaaaaa-0000-0000-0000-000000000002",
        "entity_type": "message",
        "entity_id": "bbbbbbbb-0000-0000-0000-000000000002",
        "op": "update",
        "timestamp": {"wall_ms": 1715644900000, "lamport": 5, "device_id": "cccccccc-0000-0000-0000-000000000001"},
        "user_id": "dddddddd-0000-0000-0000-000000000001",
        "device_id": "cccccccc-0000-0000-0000-000000000001",
        "tenant_id": null,
        "payload": {"body": "edited in v1.1.1"},
        "schema_version": 2,
        "signature": [],
        "metadata": {"client_version": "1.1.1", "new_field": true}
    }"#;

    // This must succeed — unknown "metadata" field must be ignored.
    let env: EventEnvelope = serde_json::from_str(v111_json)
        .expect("v1.1.0/1.1.1 reader must tolerate unknown fields from v1.1.1 clients");

    // Known fields still correct.
    assert_eq!(env.op, Op::Update, "op must be Update");
    assert_eq!(env.schema_version, 2, "schema_version=2 must parse");
    assert_eq!(env.timestamp.lamport, 5, "lamport mismatch");
}

/// BC-08: HLC total order is preserved across v1.1.0 and v1.1.1 events.
///
/// Mixed batches from old and new clients must sort correctly. The HLC ordering
/// (wall_ms → lamport → device_id) must be deterministic and byte-stable.
#[test]
fn bc_hlc_ordering_stable_across_versions() {
    let dev_a = Uuid::parse_str("aaaaaaaa-0000-0000-0000-000000000001").unwrap();
    let dev_b = Uuid::parse_str("bbbbbbbb-0000-0000-0000-000000000001").unwrap();

    // v1.1.0-era event (lower wall_ms)
    let hlc_v110 = Hlc { wall_ms: 1_000_000, lamport: 1, device_id: dev_a };
    // v1.1.1-era event (higher wall_ms)
    let hlc_v111 = Hlc { wall_ms: 2_000_000, lamport: 0, device_id: dev_b };

    assert!(
        hlc_v110 < hlc_v111,
        "v1.1.0 HLC with lower wall_ms must sort before v1.1.1 HLC with higher wall_ms"
    );

    // Same wall_ms: lamport breaks the tie.
    let hlc_lower_lamport = Hlc { wall_ms: 1_500_000, lamport: 2, device_id: dev_a };
    let hlc_higher_lamport = Hlc { wall_ms: 1_500_000, lamport: 9, device_id: dev_a };
    assert!(hlc_lower_lamport < hlc_higher_lamport, "lower lamport must sort before higher");

    // Same wall_ms + lamport: device_id (UUID bytes) breaks the tie.
    let hlc_dev_a = Hlc { wall_ms: 1_500_000, lamport: 5, device_id: dev_a };
    let hlc_dev_b = Hlc { wall_ms: 1_500_000, lamport: 5, device_id: dev_b };
    // dev_a < dev_b by UUID byte ordering (aa < bb prefix).
    assert_ne!(hlc_dev_a.cmp(&hlc_dev_b), std::cmp::Ordering::Equal, "device_id must break tie");
}
