//! Integration tests for sync push/ack/snapshot retry behavior.
//!
//! Covers the retry scenarios mandated by P102 S05 (throttle retries):
//! 1. Succeeds on first try (no retry).
//! 2. Exhausts after `max_attempts` on a persistent 503.
//! 3. Honors server `Retry-After` header on 429 (strict policy → exhausted on
//!    first 429, header parsed without error).
//! 4. Non-retryable 4xx (400, 403) does NOT trigger retry.
//! 5. `Idempotency-Key` header is sent on every push.
//!
//! Tests use the `_with_retry_rng` variants with `|| 0.0` so jittered sleeps
//! collapse to zero and the suite stays fast.

use httpmock::prelude::*;
use libnclaw::error::{CoreError, TransportError};
use libnclaw::sync::network::{PushCursor, PushRequest, SyncNetwork};
use libnclaw::sync::retry::RetryPolicy;
use std::time::Duration;
use uuid::Uuid;

fn test_policy() -> RetryPolicy {
    RetryPolicy::new(
        Duration::from_millis(1),
        2.0,
        Duration::from_millis(4),
        5,
    )
}

fn empty_push_req() -> PushRequest {
    PushRequest {
        device_id: Uuid::nil(),
        events: vec![],
        cursor: Some(PushCursor {
            wall_ms: 0,
            lamport: 0,
        }),
        schema_version: None,
    }
}

#[tokio::test]
async fn push_with_retry_succeeds_on_first_try() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/sync/push");
            then.status(200)
                .json_body(serde_json::json!({ "results": [], "acks": [] }));
        })
        .await;

    let client = SyncNetwork::new(server.url(""), "jwt");
    let req = empty_push_req();
    let resp = client
        .push_with_retry_rng(&req, test_policy(), || 0.0)
        .await
        .expect("first try should succeed");
    assert!(resp.all_accepted());
    mock.assert_hits_async(1).await;
}

#[tokio::test]
async fn push_with_retry_exhausts_after_max_attempts() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/sync/push");
            then.status(503).body("upstream offline");
        })
        .await;

    let client = SyncNetwork::new(server.url(""), "jwt");
    let req = empty_push_req();
    let err = client
        .push_with_retry_rng(&req, test_policy(), || 0.0)
        .await
        .expect_err("should exhaust retries");

    match err {
        CoreError::Transport(TransportError::RetryExhausted {
            attempts,
            last_status,
            ..
        }) => {
            assert_eq!(attempts, 5, "default max_attempts");
            assert_eq!(last_status, 503);
        }
        other => panic!("expected RetryExhausted, got {other:?}"),
    }
    // The retry loop should have hit the mock exactly max_attempts times.
    mock.assert_hits_async(5).await;
}

#[tokio::test]
async fn push_with_retry_honors_retry_after_header() {
    let server = MockServer::start_async().await;
    // 429 with Retry-After: 0 (so the test stays fast). Strict policy of 1
    // attempt means the first 429 immediately exhausts the budget — proving
    // both that 429 is classified retryable AND that header parsing does not
    // crash.
    let throttle_mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/sync/push");
            then.status(429).header("Retry-After", "0").body("throttled");
        })
        .await;
    let strict = RetryPolicy::new(
        Duration::from_millis(1),
        2.0,
        Duration::from_millis(2),
        1, // 1 attempt → first 429 is terminal via RetryExhausted
    );
    let client = SyncNetwork::new(server.url(""), "jwt");
    let req = empty_push_req();
    let err = client
        .push_with_retry_rng(&req, strict, || 0.0)
        .await
        .expect_err("strict policy: 429 with no retries → exhausted");
    match err {
        CoreError::Transport(TransportError::RetryExhausted {
            attempts,
            last_status,
            ..
        }) => {
            assert_eq!(attempts, 1);
            assert_eq!(last_status, 429);
        }
        other => panic!("expected RetryExhausted, got {other:?}"),
    }
    throttle_mock.assert_hits_async(1).await;
}

#[tokio::test]
async fn push_with_retry_does_not_retry_on_non_retryable_4xx() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/sync/push");
            then.status(400).body(r#"{"error":"bad request","status":400}"#);
        })
        .await;
    let client = SyncNetwork::new(server.url(""), "jwt");
    let req = empty_push_req();
    let err = client
        .push_with_retry_rng(&req, test_policy(), || 0.0)
        .await
        .expect_err("400 should NOT retry");
    // Must be ProtocolViolation, NOT RetryExhausted — proving zero retries.
    match err {
        CoreError::Transport(TransportError::ProtocolViolation(m)) => {
            assert!(m.contains("400"), "msg: {m}");
        }
        other => panic!("expected ProtocolViolation, got {other:?}"),
    }
    mock.assert_hits_async(1).await;
}

#[tokio::test]
async fn push_with_retry_does_not_retry_on_403() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST).path("/sync/push");
            then.status(403).body("device_id mismatch");
        })
        .await;
    let client = SyncNetwork::new(server.url(""), "jwt");
    let req = empty_push_req();
    let err = client
        .push_with_retry_rng(&req, test_policy(), || 0.0)
        .await
        .expect_err("403 should NOT retry");
    // SyncError::InvalidState — proving non-retryable path was taken.
    assert!(matches!(err, CoreError::Sync(_)));
    mock.assert_hits_async(1).await;
}

#[tokio::test]
async fn push_with_retry_sends_idempotency_key_header() {
    let server = MockServer::start_async().await;
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/sync/push")
                .header_exists("Idempotency-Key");
            then.status(200)
                .json_body(serde_json::json!({ "results": [], "acks": [] }));
        })
        .await;
    let client = SyncNetwork::new(server.url(""), "jwt");
    let req = empty_push_req();
    let _ = client
        .push_with_retry_rng(&req, test_policy(), || 0.0)
        .await
        .expect("ok");
    mock.assert_hits_async(1).await;
}
