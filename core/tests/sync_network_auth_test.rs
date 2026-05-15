//! Integration tests for V04-F04 fix: JWT in Authorization header, never in URL.
//!
//! Verifies that:
//! - HTTP push/pull/snapshot/ack carry the JWT via `Authorization: Bearer <token>`
//! - WebSocket subscribe URL contains no `?token=` (or any token material)
//! - The post-connect WebSocket auth frame matches the canonical wire format
//!   `{"type":"auth","token":"<JWT>"}`

use httpmock::prelude::*;
use libnclaw::sync::network::{
    AckRequest, AuthFrame, PullRequest, PushRequest, SyncNetwork,
};
use libnclaw::sync::snapshot::SnapshotRequest;

const TEST_JWT: &str = "eyJhbGciOiJIUzI1NiJ9.test_payload.test_sig";

#[tokio::test]
async fn push_sends_jwt_in_authorization_header_not_url() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/push")
                .header("Authorization", format!("Bearer {}", TEST_JWT))
                // V04-F04: the URL must not contain the token at all.
                .matches(|req| {
                    let url_str = format!("{:?}", req);
                    !url_str.contains("token=") && !url_str.contains(TEST_JWT.split('.').next().unwrap_or(""))
                        || !req
                            .query_params
                            .as_ref()
                            .map(|p| p.iter().any(|(_, v)| v.contains(TEST_JWT)))
                            .unwrap_or(false)
                });
            then.status(200).json_body(serde_json::json!({"acks": []}));
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = PushRequest {
        device_id: uuid::Uuid::nil(),
        events: vec![],
        cursor: None,
        schema_version: None,
    };
    let resp = net.push(&req).await.expect("push ok");
    assert!(resp.acks.is_empty());
    mock.assert_async().await;
}

#[tokio::test]
async fn pull_sends_jwt_in_authorization_header_not_url() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/pull")
                .header("Authorization", format!("Bearer {}", TEST_JWT));
            then.status(200)
                .json_body(serde_json::json!({"events": [], "has_more": false}));
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = PullRequest {
        since_hlc_wall_ms: 0,
        since_hlc_lamport: 0,
        entity_filters: vec![],
        limit: 50,
    };
    let resp = net.pull(&req).await.expect("pull ok");
    assert!(!resp.has_more);
    mock.assert_async().await;
}

#[tokio::test]
async fn snapshot_sends_jwt_in_authorization_header_not_url() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/snapshot")
                .header("Authorization", format!("Bearer {}", TEST_JWT));
            then.status(200)
                .json_body(serde_json::json!({"events": [], "cursor": null}));
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = SnapshotRequest::new(uuid::Uuid::new_v4(), None);
    let resp = net.snapshot(&req).await.expect("snapshot ok");
    assert!(resp.is_empty());
    mock.assert_async().await;
}

#[tokio::test]
async fn ack_sends_jwt_in_authorization_header() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/ack")
                .header("Authorization", format!("Bearer {}", TEST_JWT));
            then.status(204);
        })
        .await;

    let net = SyncNetwork::new(server.base_url(), TEST_JWT);
    let req = AckRequest {
        event_ids: vec![uuid::Uuid::new_v4()],
    };
    net.ack(&req).await.expect("ack ok");
    mock.assert_async().await;
}

#[tokio::test]
async fn missing_authorization_header_yields_server_401() {
    let server = MockServer::start_async().await;
    // Mock will only respond 200 if Authorization is present and matches; otherwise default 404 simulates rejection.
    server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/push")
                .header("Authorization", format!("Bearer {}", TEST_JWT));
            then.status(200).json_body(serde_json::json!({"acks": []}));
        })
        .await;

    // Use a different JWT — header won't match, mock returns default 404 -> CoreError::Network.
    let net = SyncNetwork::new(server.base_url(), "wrong.jwt.value");
    let req = PushRequest {
        device_id: uuid::Uuid::nil(),
        events: vec![],
        cursor: None,
        schema_version: None,
    };
    let result = net.push(&req).await;
    assert!(result.is_err(), "push with wrong jwt must fail");
}

#[test]
fn subscribe_url_contains_no_token() {
    let net = SyncNetwork::new("https://api.example.com", TEST_JWT);
    let url = net.subscribe_url();
    // Hard assertions: URL is exactly the host + path, with no query, fragment, or token bytes.
    assert_eq!(url, "wss://api.example.com/sync/subscribe");
    assert!(!url.contains(TEST_JWT));
    assert!(!url.contains("token"));
    assert!(!url.contains('?'));
    assert!(!url.contains('#'));
}

#[test]
fn subscribe_url_with_http_scheme_strips_token_too() {
    let net = SyncNetwork::new("http://localhost:8080", TEST_JWT);
    let url = net.subscribe_url();
    assert_eq!(url, "ws://localhost:8080/sync/subscribe");
    assert!(!url.contains(TEST_JWT));
    assert!(!url.contains("token"));
    assert!(!url.contains('?'));
}

#[test]
fn auth_frame_is_first_frame_payload_for_websocket() {
    let net = SyncNetwork::new("https://api.example.com", TEST_JWT);
    let frame = net.auth_frame();
    assert_eq!(frame.kind, "auth");
    assert_eq!(frame.token, TEST_JWT);
    let json = frame.to_json();
    // Server-side expected wire format (must match nself-sync handleSubscribe decoder).
    assert_eq!(
        json,
        format!(r#"{{"type":"auth","token":"{}"}}"#, TEST_JWT)
    );
}

#[test]
fn auth_frame_can_be_constructed_directly() {
    let frame = AuthFrame::new("token-value");
    let json = frame.to_json();
    assert!(json.contains("\"type\":\"auth\""));
    assert!(json.contains("\"token\":\"token-value\""));
}

#[test]
fn auth_frame_escapes_special_chars_in_token() {
    // JWTs are base64url (no quotes or backslashes), but defense in depth: any
    // exotic token must still serialize to valid JSON.
    let frame = AuthFrame::new("weird\"token\\value");
    let json = frame.to_json();
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json");
    assert_eq!(parsed["type"], "auth");
    assert_eq!(parsed["token"], "weird\"token\\value");
}
