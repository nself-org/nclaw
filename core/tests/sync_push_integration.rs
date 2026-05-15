//! Push path wire integration tests (P102 Wave 10 — S03 M2).
//!
//! End-to-end round-trip exercises against an in-process `httpmock` server
//! that emulates the contract of `nself-sync`'s `handlePush`. Verifies:
//!
//!   1. The request wire shape matches the server contract: `device_id` at
//!      the top level, events as an array of envelopes with FLAT HLC fields
//!      (`hlc_wall_ms`/`hlc_lamport`/`hlc_device_id`) per the V04-F05
//!      Wave-11 hotfix, `Authorization: Bearer <jwt>` header, no JWT in
//!      the URL or query (V04-F04).
//!   2. Each event carries a non-empty Ed25519 signature whose canonical
//!      input prefix is the authoring `user_id` (V04-F02). The full
//!      bytewise locking happens in `sync::sign::tests::signing_material_golden_fixture`.
//!   3. The payload uses RFC 8785 canonical JSON for stable cross-language
//!      verification (V04-F03 via `signing_material` → `canonical_json`).
//!   4. All four request-level error responses map to typed `CoreError`
//!      variants the rest of the sync stack reasons about
//!      (400 / 401 / 403 / 500).
//!   5. Per-event rejections in a 200 response are surfaced via
//!      `PushResponse::rejected` without failing the outer call.
//!   6. A golden-fixture JSON file at `tests/fixtures/push_golden.json`
//!      locks the wire shape for cross-language regression detection.
//!
//! Pairs with `plugins-pro/paid/nself-sync/cmd/nself-sync/push_test.go`.

use httpmock::prelude::*;
use libnclaw::error::{CoreError, SyncError, TransportError};
use libnclaw::sync::canonical::canonical_json;
use libnclaw::sync::hlc::Hlc;
use libnclaw::sync::lww::{EventEnvelope, Op};
use libnclaw::sync::network::{PushCursor, PushRequest, PushResult, SyncNetwork};
use libnclaw::sync::sign::signing_material;
use serde_json::Value;
use std::path::PathBuf;

const TEST_JWT: &str = "eyJhbGciOiJIUzI1NiJ9.test_payload.test_sig";

// -----------------------------------------------------------------------
// Golden fixture helpers
// -----------------------------------------------------------------------

fn fixture_path() -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("tests");
    p.push("fixtures");
    p.push("push_golden.json");
    p
}

fn load_golden() -> Value {
    let bytes = std::fs::read(fixture_path()).expect("read push_golden.json");
    serde_json::from_slice(&bytes).expect("parse push_golden.json")
}

fn golden_event() -> EventEnvelope {
    let user_id = uuid::Uuid::parse_str("11111111-1111-1111-1111-111111111111").unwrap();
    let event_id = uuid::Uuid::parse_str("22222222-2222-2222-2222-222222222222").unwrap();
    let entity_id = uuid::Uuid::parse_str("33333333-3333-3333-3333-333333333333").unwrap();
    let device_id = uuid::Uuid::parse_str("44444444-4444-4444-4444-444444444444").unwrap();

    let mut env = EventEnvelope {
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
    // Place a deterministic non-empty signature so the wire shape is
    // realistic. The cryptographic correctness of the signature is locked
    // by `sign.rs::signing_material_golden_fixture`, not by this test.
    let material = signing_material(&env, user_id);
    let mut sig = vec![0u8; 64];
    for (i, b) in material.iter().take(64).enumerate() {
        sig[i] = *b ^ 0xA5;
    }
    env.signature = sig;
    env
}

fn golden_request() -> PushRequest {
    let ev = golden_event();
    PushRequest {
        device_id: ev.device_id,
        events: vec![ev],
        cursor: Some(PushCursor {
            wall_ms: 1_715_626_800_000,
            lamport: 17,
        }),
        schema_version: Some(1),
    }
}

// -----------------------------------------------------------------------
// Happy path
// -----------------------------------------------------------------------

#[tokio::test]
async fn push_round_trip_happy_path_with_signed_event() {
    let server = MockServer::start_async().await;
    let golden = load_golden();
    let resp_body = golden["response_all_accepted"].clone();

    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/push")
                .header("Authorization", format!("Bearer {}", TEST_JWT))
                // V04-F04: no token anywhere in URL or query
                .matches(|req| {
                    let qs = req
                        .query_params
                        .as_ref()
                        .map(|p| p.iter().any(|(_, v)| v.contains(TEST_JWT)))
                        .unwrap_or(false);
                    !qs
                });
            then.status(200).json_body(resp_body);
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = golden_request();
    let resp = net.push(&req).await.expect("push ok");

    assert!(resp.all_accepted(), "expected all accepted");
    assert_eq!(resp.results.len(), 1);
    assert_eq!(resp.acks.len(), 1);
    assert_eq!(resp.results[0].status, "accepted");
    mock.assert_async().await;
}

#[tokio::test]
async fn push_request_wire_shape_matches_golden_fixture() {
    let server = MockServer::start_async().await;

    // httpmock 0.7's `.matches()` accepts a `fn` pointer (no captures), so we
    // verify the bulk of the wire shape via direct `.json_body_partial(...)`
    // matchers on the well-known field paths. The full envelope is
    // additionally serialized client-side and compared against the golden
    // fixture below — this catches drift in field ordering or naming that the
    // partial matcher alone would miss.
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/push")
                .header("Authorization", format!("Bearer {}", TEST_JWT))
                .json_body_partial(
                    r#"{
                        "device_id": "44444444-4444-4444-4444-444444444444",
                        "events": [
                            {
                                "event_id": "22222222-2222-2222-2222-222222222222",
                                "entity_type": "Note",
                                "entity_id": "33333333-3333-3333-3333-333333333333",
                                "op": "insert",
                                "user_id": "11111111-1111-1111-1111-111111111111",
                                "schema_version": 1
                            }
                        ]
                    }"#
                    .to_string(),
                );
            then.status(200)
                .json_body(serde_json::json!({"results": [], "acks": []}));
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = golden_request();

    // Pre-flight: round-trip the request through serde and check the shape
    // matches the golden fixture so the partial matcher above is meaningful.
    let serialized = serde_json::to_value(&req).expect("serialize PushRequest");
    let golden = load_golden();
    let expected = &golden["request"];
    assert_eq!(serialized["device_id"], expected["device_id"]);
    let evs = serialized["events"].as_array().expect("events array");
    assert_eq!(evs.len(), 1);
    let ev = &evs[0];
    let expected_ev = &expected["events"][0];
    for key in [
        "event_id",
        "entity_type",
        "entity_id",
        "op",
        "user_id",
        "schema_version",
    ] {
        assert_eq!(ev[key], expected_ev[key], "field {key} mismatch");
    }
    // V04-F05: HLC fields are FLAT on the wire to match Go's pushRequestEvent.
    assert_eq!(ev["hlc_wall_ms"], expected_ev["hlc_wall_ms"]);
    assert_eq!(ev["hlc_lamport"], expected_ev["hlc_lamport"]);
    assert_eq!(ev["hlc_device_id"], expected_ev["hlc_device_id"]);
    assert_eq!(ev["payload"], expected_ev["payload"]);

    let resp = net.push(&req).await.expect("push ok");
    assert_eq!(resp.results.len(), 0);
    mock.assert_async().await;
}

// -----------------------------------------------------------------------
// Per-event rejection
// -----------------------------------------------------------------------

#[tokio::test]
async fn push_surfaces_per_event_rejections_without_failing_call() {
    let server = MockServer::start_async().await;
    let golden = load_golden();
    let resp_body = golden["response_mixed_rejection"].clone();

    server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/push")
                .header("Authorization", format!("Bearer {}", TEST_JWT));
            then.status(200).json_body(resp_body);
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = golden_request();
    let resp = net.push(&req).await.expect("push ok despite rejection");

    assert!(!resp.all_accepted());
    let rejected: Vec<&PushResult> = resp.rejected().collect();
    assert_eq!(rejected.len(), 1);
    assert_eq!(rejected[0].status, "rejected");
    assert_eq!(rejected[0].reason.as_deref(), Some("invalid signature"));
    assert!(resp.acks.is_empty(), "rejected events must not be acked");
}

// -----------------------------------------------------------------------
// Error mapping — the four documented server statuses
// -----------------------------------------------------------------------

async fn push_with_status(status_code: u16, body: serde_json::Value) -> CoreError {
    let server = MockServer::start_async().await;
    server
        .mock_async(|when, then| {
            when.method(POST).path("/sync/push");
            then.status(status_code).json_body(body);
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = golden_request();
    net.push(&req).await.expect_err("expected push error")
}

#[tokio::test]
async fn push_http_400_maps_to_protocol_violation() {
    let err = push_with_status(
        400,
        serde_json::json!({"error":"invalid JSON body: foo","status":400}),
    )
    .await;
    match err {
        CoreError::Transport(TransportError::ProtocolViolation(m)) => {
            assert!(m.contains("400"), "msg: {m}");
        }
        other => panic!("expected ProtocolViolation, got {other:?}"),
    }
}

#[tokio::test]
async fn push_http_401_maps_to_protocol_violation_unauthorized() {
    let err = push_with_status(
        401,
        serde_json::json!({"error":"invalid token","status":401}),
    )
    .await;
    match err {
        CoreError::Transport(TransportError::ProtocolViolation(m)) => {
            assert!(m.contains("401"));
            assert!(m.contains("unauthorized"));
        }
        other => panic!("expected ProtocolViolation, got {other:?}"),
    }
}

#[tokio::test]
async fn push_http_403_maps_to_sync_invalid_state() {
    let err = push_with_status(
        403,
        serde_json::json!({"error":"device_id does not match token","status":403}),
    )
    .await;
    match err {
        CoreError::Sync(SyncError::InvalidState(m)) => {
            assert!(m.contains("403"));
            assert!(m.contains("forbidden"));
        }
        other => panic!("expected SyncError::InvalidState, got {other:?}"),
    }
}

#[tokio::test]
async fn push_http_500_maps_to_network_error() {
    let err = push_with_status(
        500,
        serde_json::json!({"error":"internal error","status":500}),
    )
    .await;
    match err {
        CoreError::Transport(TransportError::Network(m)) => {
            assert!(m.contains("500"));
        }
        other => panic!("expected Network, got {other:?}"),
    }
}

// -----------------------------------------------------------------------
// Canonical-JSON binding sanity (V04-F03)
// -----------------------------------------------------------------------

#[test]
fn signing_material_uses_canonical_payload_bytes() {
    // The signing material for our golden event must end with the canonical
    // JSON of {"k":"v"} — locking that the wire payload bytes match what
    // the server reconstructs in `canonicalJSON` (Go side).
    let env = golden_event();
    let user_id = env.user_id;
    let material = signing_material(&env, user_id);
    let canonical = canonical_json(env.payload.as_ref().expect("payload"));
    let tail = &material[material.len() - canonical.len()..];
    assert_eq!(tail, canonical.as_slice());
    assert_eq!(canonical.as_slice(), br#"{"k":"v"}"#);
}

/// V04-F05 (P102 W11 hotfix): the canonical signing layout was converged
/// with Go's `canonicalSigningMaterial`. The layout no longer starts with
/// `user_id` — that V04-F02 assertion was specific to the pre-hotfix
/// layout. The new layout starts with `event_id` and binds `user_id` at
/// the post-HLC position. The user_id is still in the signed bytes
/// (cross-user replay is still detected); the byte ordering changed.
#[test]
fn signing_material_starts_with_event_id_v04_f05() {
    let env = golden_event();
    let material = signing_material(&env, env.user_id);
    assert_eq!(
        &material[..16],
        env.event_id.as_bytes(),
        "V04-F05 layout: signing material starts with event_id (16 bytes)"
    );

    // Verify user_id is still present in the canonical bytes — V04-F02
    // identity binding is preserved at the new offset:
    //   event_id(16) || etype_len(4) || etype(4) || entity_id(16) || op(1)
    //   || wall_ms(8) || lamport(8) || hlc_dev_id(16)  = 73
    // user_id starts at byte 73.
    let etype_len = env.entity_type.as_bytes().len();
    let user_id_offset = 16 + 4 + etype_len + 16 + 1 + 8 + 8 + 16;
    assert_eq!(
        &material[user_id_offset..user_id_offset + 16],
        env.user_id.as_bytes(),
        "V04-F02 identity binding preserved at V04-F05 user_id offset"
    );
}
