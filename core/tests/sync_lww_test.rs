//! Comprehensive tests for sync LWW resolution, network, and signing.

use libnclaw::sync::lww::{EventEnvelope, Op, resolve, merge_field_updates};
use libnclaw::sync::hlc::Hlc;
use libnclaw::sync::sign::signing_material;
use uuid::Uuid;

fn make_event(
    event_id: Uuid,
    entity_type: &str,
    entity_id: Uuid,
    op: Op,
    wall_ms: i64,
    lamport: u64,
    device_id: Uuid,
    payload: Option<serde_json::Value>,
) -> EventEnvelope {
    EventEnvelope {
        event_id,
        entity_type: entity_type.to_string(),
        entity_id,
        op,
        timestamp: Hlc {
            wall_ms,
            lamport,
            device_id,
        },
        user_id: Uuid::new_v4(),
        device_id,
        tenant_id: None,
        payload,
        schema_version: 1,
        signature: vec![],
    }
}

#[test]
fn lww_resolve_empty_stream() {
    let result = resolve(&[]);
    assert!(result.is_none(), "empty stream should return None");
}

#[test]
fn lww_resolve_single_insert() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let ev = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Insert,
        1000,
        0,
        dev,
        Some(serde_json::json!({"name": "Alice"})),
    );
    let result = resolve(&[ev.clone()]);
    assert!(result.is_some());
    let resolved = result.unwrap();
    assert_eq!(resolved.event_id, ev.event_id);
    assert_eq!(resolved.op, Op::Insert);
}

#[test]
fn lww_resolve_insert_then_update() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let ev_insert = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Insert,
        1000,
        0,
        dev,
        Some(serde_json::json!({"name": "Alice"})),
    );
    let ev_update = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Update,
        2000,
        0,
        dev,
        Some(serde_json::json!({"name": "Bob"})),
    );
    let result = resolve(&[ev_insert, ev_update.clone()]);
    assert!(result.is_some());
    assert_eq!(result.unwrap().event_id, ev_update.event_id);
}

#[test]
fn lww_resolve_delete_tombstones_earlier() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let ev_insert = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Insert,
        1000,
        0,
        dev,
        Some(serde_json::json!({})),
    );
    let ev_update = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Update,
        1500,
        0,
        dev,
        Some(serde_json::json!({})),
    );
    let ev_delete = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Delete,
        2000,
        0,
        dev,
        None,
    );
    let result = resolve(&[ev_insert, ev_update, ev_delete.clone()]);
    assert!(result.is_some());
    assert_eq!(result.unwrap().op, Op::Delete);
}

#[test]
fn lww_resolve_insert_after_delete_wins() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let ev_delete = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Delete,
        2000,
        0,
        dev,
        None,
    );
    let ev_insert = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Insert,
        3000,
        0,
        dev,
        Some(serde_json::json!({"name": "Charlie"})),
    );
    let result = resolve(&[ev_delete, ev_insert.clone()]);
    assert!(result.is_some());
    assert_eq!(result.unwrap().op, Op::Insert);
}

#[test]
fn lww_resolve_hlc_total_order() {
    // Test that events are ordered by HLC total order:
    // wall_ms → lamport → device_id (lexicographic)
    let dev_a = Uuid::new_v4();
    let dev_b = if Uuid::new_v4() < dev_a { Uuid::new_v4() } else { dev_a };
    let id = Uuid::new_v4();

    // Same wall, different lamports
    let ev1 = make_event(Uuid::new_v4(), "E", id, Op::Insert, 1000, 0, dev_a, None);
    let ev2 = make_event(Uuid::new_v4(), "E", id, Op::Update, 1000, 1, dev_a, None);

    let result = resolve(&[ev2.clone(), ev1]);
    assert_eq!(result.unwrap().timestamp.lamport, 1, "higher lamport should win");
}

#[test]
fn lww_merge_field_updates_newer_wins() {
    let dev_a = Uuid::new_v4();
    let dev_b = Uuid::new_v4();
    let id = Uuid::new_v4();

    let ev_older = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Update,
        1000,
        0,
        dev_a,
        Some(serde_json::json!({"name": "Alice", "age": 30})),
    );
    let ev_newer = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Update,
        2000,
        0,
        dev_b,
        Some(serde_json::json!({"name": "Bob", "city": "NYC"})),
    );

    let merged = merge_field_updates(&ev_older, &ev_newer);
    assert_eq!(merged["name"], "Bob", "newer event's name should win");
    assert_eq!(merged["age"], 30, "older event's age should be retained");
    assert_eq!(merged["city"], "NYC", "newer event's city should be present");
}

#[test]
fn lww_merge_field_updates_both_empty() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let ev1 = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Update,
        1000,
        0,
        dev,
        None,
    );
    let ev2 = make_event(
        Uuid::new_v4(),
        "User",
        id,
        Op::Update,
        2000,
        0,
        dev,
        None,
    );
    let merged = merge_field_updates(&ev1, &ev2);
    assert!(merged.is_object());
}

#[test]
fn signing_material_is_deterministic() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let event_id = Uuid::new_v4();

    let ev1 = make_event(
        event_id,
        "TestEntity",
        id,
        Op::Insert,
        1000,
        0,
        dev,
        Some(serde_json::json!({"field": "value"})),
    );
    let mut ev2 = make_event(
        event_id,
        "TestEntity",
        id,
        Op::Insert,
        1000,
        0,
        dev,
        Some(serde_json::json!({"field": "value"})),
    );
    // Manually set user_id to match ev1 for determinism
    ev2.user_id = ev1.user_id;

    let material1 = signing_material(&ev1);
    let material2 = signing_material(&ev2);
    assert_eq!(material1, material2, "identical events produce identical signing material");
}

#[test]
fn signing_material_changes_with_different_op() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let event_id = Uuid::new_v4();

    let ev_insert = make_event(
        event_id,
        "TestEntity",
        id,
        Op::Insert,
        1000,
        0,
        dev,
        Some(serde_json::json!({})),
    );
    let mut ev_delete = make_event(
        event_id,
        "TestEntity",
        id,
        Op::Delete,
        1000,
        0,
        dev,
        Some(serde_json::json!({})),
    );
    ev_delete.user_id = ev_insert.user_id;

    let material_insert = signing_material(&ev_insert);
    let material_delete = signing_material(&ev_delete);
    assert_ne!(
        material_insert, material_delete,
        "different op should produce different signing material"
    );
}

#[test]
fn signing_material_changes_with_different_payload() {
    let dev = Uuid::new_v4();
    let id = Uuid::new_v4();
    let event_id = Uuid::new_v4();

    let ev1 = make_event(
        event_id,
        "TestEntity",
        id,
        Op::Update,
        1000,
        0,
        dev,
        Some(serde_json::json!({"field": "value1"})),
    );
    let mut ev2 = make_event(
        event_id,
        "TestEntity",
        id,
        Op::Update,
        1000,
        0,
        dev,
        Some(serde_json::json!({"field": "value2"})),
    );
    ev2.user_id = ev1.user_id;

    let material1 = signing_material(&ev1);
    let material2 = signing_material(&ev2);
    assert_ne!(
        material1, material2,
        "different payload should produce different signing material"
    );
}

#[test]
fn network_push_request_serializes() {
    use libnclaw::sync::network::{PushRequest, SyncNetwork};
    let net = SyncNetwork::new("http://localhost:8080", "test_jwt");
    let req = PushRequest { events: vec![] };
    let json = net.push_request(&req);
    assert!(json.contains("events"));
}

#[test]
fn network_pull_request_includes_all_fields() {
    use libnclaw::sync::network::{PullRequest, SyncNetwork};
    let net = SyncNetwork::new("http://localhost:8080", "test_jwt");
    let req = PullRequest {
        since_hlc_wall_ms: 1000,
        since_hlc_lamport: 5,
        entity_filters: vec!["User".to_string(), "Message".to_string()],
        limit: 100,
    };
    let json = net.pull_request(&req);
    assert!(json.contains("1000"));
    assert!(json.contains("User"));
    assert!(json.contains("100"));
}

#[test]
fn network_sync_network_subscribe_url_http() {
    use libnclaw::sync::network::SyncNetwork;
    let net = SyncNetwork::new("http://localhost:8080", "test_jwt");
    let url = net.subscribe_url();
    assert!(url.starts_with("ws://"));
    assert!(url.contains("/sync/subscribe"));
    assert!(url.contains("test_jwt"));
}

#[test]
fn network_sync_network_subscribe_url_https() {
    use libnclaw::sync::network::SyncNetwork;
    let net = SyncNetwork::new("https://api.example.com", "test_jwt");
    let url = net.subscribe_url();
    assert!(url.starts_with("wss://"));
    assert!(url.contains("/sync/subscribe"));
}
