//! Network push/pull/subscribe wrappers for sync protocol.
//!
//! HTTP endpoints for pushing local changes and pulling remote changes,
//! plus WebSocket subscription URL generation for real-time sync.
//!
//! ## Authentication (V04-F04 fix)
//!
//! The JWT is **never** placed in any URL (query string, path, or fragment).
//! URLs are logged at every hop (nginx access logs, proxy logs, Cloudflare logs,
//! browser history, OS-level network traces). Embedding the bearer token in a URL
//! leaks the credential to every observer in the chain.
//!
//! Authentication scheme:
//!
//! - **HTTP endpoints** (`POST /sync/push`, `POST /sync/pull`, `POST /sync/snapshot`,
//!   `POST /sync/ack`): the JWT is sent in the `Authorization: Bearer <JWT>` header.
//! - **WebSocket** (`/sync/subscribe`): the connection is upgraded with **no token in
//!   the URL**. Immediately after the upgrade, the client sends a single text frame
//!   containing the auth payload:
//!
//!   ```json
//!   {"type":"auth","token":"<JWT>"}
//!   ```
//!
//!   The server validates the frame within a 5-second deadline (see nself-sync
//!   `handleSubscribe`); failure to send a valid auth frame within that window
//!   results in a server-initiated close with code 4001.

use crate::error::{CoreError, SyncError, TransportError};
use crate::sync::lww::EventEnvelope;
use crate::sync::retry::{
    is_retryable_status, parse_retry_after, RetryDecision, RetryPolicy,
};
use crate::sync::snapshot::{SnapshotRequest, SnapshotResponse};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Request payload for pushing events to the server.
///
/// `device_id` is required by the server (`handlePush` rejects an empty value
/// with HTTP 400 and a mismatch with the JWT `did` claim with HTTP 403). It is
/// the identifier of the device that produced the operations — the same value
/// that appears in the JWT `did` claim and in each envelope's HLC `device_id`.
///
/// `cursor` is informational only — server-side dedup is by `event_id`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushRequest {
    pub device_id: uuid::Uuid,
    pub events: Vec<EventEnvelope>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cursor: Option<PushCursor>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub schema_version: Option<u32>,
}

/// Optional per-device cursor checkpoint included in push for diagnostics.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PushCursor {
    pub wall_ms: i64,
    pub lamport: u64,
}

/// Per-event status returned by the server. Status is one of
/// `"accepted"` (newly inserted), `"duplicate"` (already present, idempotent
/// re-push), or `"rejected"` (the `reason` field carries the cause —
/// `"invalid signature"`, `"user_id mismatch"`, `"store error"`, etc).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PushResult {
    pub event_id: uuid::Uuid,
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// Acknowledgment of a single pushed event.
///
/// Retained for callers that want a typed view over the v1.1.0 `acks` field;
/// new code should prefer [`PushResult`] which carries the rejection reason.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EventAck {
    pub event_id: uuid::Uuid,
    pub status: String,
}

/// Response from a push operation. Mirrors `pushResponse` in
/// `plugins-pro/paid/nself-sync/cmd/nself-sync/main.go`.
///
/// - `results` carries one entry per event in the request, including rejected
///   ones (rejection does not fail the whole request).
/// - `acks` is the v1.1.0-compatible flat list of accepted `event_id` values.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushResponse {
    #[serde(default)]
    pub results: Vec<PushResult>,
    #[serde(default)]
    pub acks: Vec<uuid::Uuid>,
}

impl PushResponse {
    /// Iterate over events the server rejected with a non-accepted status.
    pub fn rejected(&self) -> impl Iterator<Item = &PushResult> {
        self.results
            .iter()
            .filter(|r| r.status != "accepted" && r.status != "duplicate")
    }

    /// True when every result is accepted or duplicate (no rejections).
    pub fn all_accepted(&self) -> bool {
        self.rejected().next().is_none()
    }
}

/// Request payload for pulling events from the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullRequest {
    pub since_hlc_wall_ms: i64,
    pub since_hlc_lamport: u64,
    pub entity_filters: Vec<String>,
    pub limit: u32,
}

/// Response from a pull operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullResponse {
    pub events: Vec<EventEnvelope>,
    pub has_more: bool,
}

/// Acknowledgment request — confirms that previously pulled events were applied.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AckRequest {
    pub event_ids: Vec<uuid::Uuid>,
}

/// First frame the client sends after a successful WebSocket upgrade. Carries the
/// JWT off the URL and into the WebSocket data channel where it is not logged.
///
/// Wire format (must match the server's `handleSubscribe` decoder):
///
/// ```json
/// {"type":"auth","token":"<JWT>"}
/// ```
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AuthFrame {
    #[serde(rename = "type")]
    pub kind: String,
    pub token: String,
}

impl AuthFrame {
    /// Build an auth frame for the supplied JWT.
    pub fn new(jwt: impl Into<String>) -> Self {
        Self {
            kind: "auth".to_string(),
            token: jwt.into(),
        }
    }

    /// Serialize to the canonical wire JSON string.
    pub fn to_json(&self) -> String {
        // type and token are both ASCII; serialization is infallible in practice.
        serde_json::to_string(self).unwrap_or_else(|_| {
            // Fall back to a hand-rolled payload that still meets the wire contract.
            format!(
                "{{\"type\":\"auth\",\"token\":\"{}\"}}",
                self.token.replace('\\', "\\\\").replace('"', "\\\"")
            )
        })
    }
}

/// Sync network client for push/pull/subscribe operations.
///
/// The `jwt` field is treated as a bearer credential. It is attached to HTTP requests
/// via the `Authorization` header and to WebSocket sessions via a post-connect auth
/// frame. It MUST NOT be embedded in any URL emitted by this struct.
pub struct SyncNetwork {
    pub server_url: String,
    pub jwt: String,
    pub client: reqwest::Client,
}

impl SyncNetwork {
    /// Create a new sync network client.
    pub fn new(server_url: impl Into<String>, jwt: impl Into<String>) -> Self {
        Self {
            server_url: server_url.into(),
            jwt: jwt.into(),
            client: reqwest::Client::new(),
        }
    }

    /// Serialize a push request body. Pair with [`SyncNetwork::push`] for the full
    /// network round-trip; this helper exists for callers that want to inspect the
    /// payload (e.g. for signing or logging) before submission.
    pub fn push_request(&self, req: &PushRequest) -> String {
        serde_json::to_string(req).unwrap_or_else(|_| "{}".to_string())
    }

    /// Serialize a pull request body. See [`SyncNetwork::push_request`].
    pub fn pull_request(&self, req: &PullRequest) -> String {
        serde_json::to_string(req).unwrap_or_else(|_| "{}".to_string())
    }

    /// Build the URL for the WebSocket subscription endpoint.
    ///
    /// **The URL contains NO authentication material.** The JWT is delivered via a
    /// post-connect auth frame (see [`AuthFrame`]). Callers MUST send the auth frame
    /// returned by [`SyncNetwork::auth_frame`] as the first WebSocket message after
    /// the upgrade completes; the server closes the connection with code 4001 if a
    /// valid frame does not arrive within 5 seconds.
    pub fn subscribe_url(&self) -> String {
        let s = self
            .server_url
            .replacen("http://", "ws://", 1)
            .replacen("https://", "wss://", 1);
        format!("{}/sync/subscribe", s)
    }

    /// Build the post-connect WebSocket auth frame for this client's JWT.
    ///
    /// Send the JSON returned by [`AuthFrame::to_json`] as the first text frame
    /// after the WebSocket upgrade completes.
    pub fn auth_frame(&self) -> AuthFrame {
        AuthFrame::new(&self.jwt)
    }

    /// POST a push request to `{server_url}/sync/push`.
    ///
    /// The JWT is delivered exclusively in the `Authorization: Bearer <JWT>` header
    /// (V04-F04 — never in URL). Each event in `req.events` MUST already carry a
    /// signature produced by [`crate::sync::sign::sign`] using the canonical
    /// material from [`crate::sync::sign::signing_material`] (V04-F02 binds the
    /// authoring `user_id` into the signed bytes; V04-F03 uses RFC 8785 canonical
    /// JSON for the payload).
    ///
    /// Returns the server's [`PushResponse`] — note that the call is `Ok` even
    /// when individual events were rejected (rejections appear in `results` and
    /// are visible via [`PushResponse::rejected`]). The call returns `Err` only
    /// for request-level failures.
    ///
    /// Error mapping mirrors the server contract in `handlePush`:
    ///
    /// | HTTP | Variant | Cause |
    /// |------|---------|-------|
    /// | 400  | `TransportError::ProtocolViolation` | Malformed body or missing `device_id` |
    /// | 401  | `TransportError::ProtocolViolation("unauthorized: ...")` | Missing or invalid bearer |
    /// | 403  | `SyncError::InvalidState`            | `device_id` mismatch or device not registered |
    /// | 413  | `TransportError::ProtocolViolation` | Request body exceeded 1 MiB cap |
    /// | 5xx  | `TransportError::Network`           | Server-side failure (retryable by caller) |
    /// | other| `TransportError::Network`           | Unexpected status |
    pub async fn push(&self, req: &PushRequest) -> Result<PushResponse, CoreError> {
        let url = format!("{}/sync/push", self.server_url);
        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.jwt))
            .header("X-NClaw-Sync-Version", "1")
            .json(req)
            .send()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("push send: {e}"))))?;

        let status = resp.status();
        if !status.is_success() {
            let code = status.as_u16();
            let body = resp.text().await.unwrap_or_default();
            return Err(map_push_status(code, &body));
        }
        resp.json::<PushResponse>()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("push decode: {e}"))))
    }

    /// POST a pull request to `{server_url}/sync/pull`.
    pub async fn pull(&self, req: &PullRequest) -> Result<PullResponse, CoreError> {
        let url = format!("{}/sync/pull", self.server_url);
        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.jwt))
            .header("X-NClaw-Sync-Version", "1")
            .json(req)
            .send()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("pull send: {e}"))))?;
        if !resp.status().is_success() {
            return Err(CoreError::Transport(TransportError::Network(format!(
                "pull http {}",
                resp.status().as_u16()
            ))));
        }
        resp.json::<PullResponse>()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("pull decode: {e}"))))
    }

    /// POST a snapshot request to `{server_url}/sync/snapshot`.
    pub async fn snapshot(
        &self,
        req: &SnapshotRequest,
    ) -> Result<SnapshotResponse, CoreError> {
        let url = format!("{}/sync/snapshot", self.server_url);
        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.jwt))
            .header("X-NClaw-Sync-Version", "1")
            .json(req)
            .send()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("snapshot send: {e}"))))?;
        if !resp.status().is_success() {
            return Err(CoreError::Transport(TransportError::Network(format!(
                "snapshot http {}",
                resp.status().as_u16()
            ))));
        }
        resp.json::<SnapshotResponse>()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("snapshot decode: {e}"))))
    }

    // (no helpers between methods — `map_push_status` lives at module scope below)

    /// POST an ack request to `{server_url}/sync/ack` confirming applied events.
    pub async fn ack(&self, req: &AckRequest) -> Result<(), CoreError> {
        let url = format!("{}/sync/ack", self.server_url);
        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.jwt))
            .header("X-NClaw-Sync-Version", "1")
            .json(req)
            .send()
            .await
            .map_err(|e| CoreError::Transport(TransportError::Network(format!("ack send: {e}"))))?;
        if !resp.status().is_success() {
            return Err(CoreError::Transport(TransportError::Network(format!(
                "ack http {}",
                resp.status().as_u16()
            ))));
        }
        Ok(())
    }
}

/// Compute the Idempotency-Key value for a push request. The key is derived
/// from the sorted event IDs in the request so that an identical retry
/// produces the same key — letting the server (W9-T2 already idempotent on
/// `event_id`) treat the second arrival as a duplicate at the request layer as
/// well as the row layer. Belt-plus-suspenders.
///
/// Format: `nclaw-push-<hex>` where `<hex>` is the SHA-256 of the
/// canonical-sorted event-id list. 16 bytes (32 hex chars) is plenty of
/// uniqueness for this purpose.
fn idempotency_key_for_push(req: &PushRequest) -> String {
    use sha2::{Digest, Sha256};
    let mut ids: Vec<[u8; 16]> = req.events.iter().map(|e| *e.event_id.as_bytes()).collect();
    ids.sort_unstable();
    let mut hasher = Sha256::new();
    hasher.update(req.device_id.as_bytes());
    for id in &ids {
        hasher.update(id);
    }
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(32);
    for b in &digest[..16] {
        use std::fmt::Write;
        let _ = write!(&mut hex, "{:02x}", b);
    }
    format!("nclaw-push-{hex}")
}

/// Default `rand` source used by retry helpers — full jitter in [0.0, 1.0).
fn rand_unit() -> f64 {
    use rand::Rng;
    rand::thread_rng().gen::<f64>()
}

impl SyncNetwork {
    /// POST a push request with bounded retry on transient failures.
    ///
    /// Retries on HTTP 408, 429, and 5xx, and on network/connect/timeout
    /// failures. Permanent client errors (400 / 401 / 403 / 413) bubble up
    /// immediately. Honors `Retry-After` on 429 / 503.
    ///
    /// Adds an `Idempotency-Key` header derived from the request's event ids
    /// so that the server can dedupe at the request layer in addition to the
    /// per-event `event_id` dedup. The same request retried yields the same
    /// key.
    pub async fn push_with_retry(
        &self,
        req: &PushRequest,
        policy: RetryPolicy,
    ) -> Result<PushResponse, CoreError> {
        self.push_with_retry_rng(req, policy, rand_unit).await
    }

    /// Variant of [`Self::push_with_retry`] that takes an injectable random
    /// source so tests can produce deterministic backoffs without sleeping.
    pub async fn push_with_retry_rng<R>(
        &self,
        req: &PushRequest,
        policy: RetryPolicy,
        mut rng: R,
    ) -> Result<PushResponse, CoreError>
    where
        R: FnMut() -> f64,
    {
        let url = format!("{}/sync/push", self.server_url);
        let idem_key = idempotency_key_for_push(req);

        let mut attempt: u32 = 0;
        // last_status / last_message track the most recent transient failure so
        // that, if the retry budget is exhausted, the surfaced `RetryExhausted`
        // error carries actionable diagnostics. On a successful retry the
        // values are simply overwritten — that's the expected lifecycle, hence
        // the lint suppression below.
        #[allow(unused_assignments)]
        let mut last_status: u16 = 0;
        #[allow(unused_assignments)]
        let mut last_message: String = String::new();

        loop {
            let send_result = self
                .client
                .post(&url)
                .header("Authorization", format!("Bearer {}", self.jwt))
                .header("X-NClaw-Sync-Version", "1")
                .header("Idempotency-Key", &idem_key)
                .json(req)
                .send()
                .await;

            // Network-level failure (no response).
            let resp = match send_result {
                Ok(r) => r,
                Err(e) => {
                    last_status = 0;
                    last_message = format!("push send: {e}");
                    if policy.should_retry(attempt) == RetryDecision::Retry {
                        sleep_jittered(&policy, attempt, None, &mut rng).await;
                        attempt += 1;
                        continue;
                    } else {
                        return Err(CoreError::Transport(TransportError::RetryExhausted {
                            attempts: attempt + 1,
                            last_status,
                            last_message,
                        }));
                    }
                }
            };

            let status = resp.status();
            let code = status.as_u16();
            if status.is_success() {
                return resp.json::<PushResponse>().await.map_err(|e| {
                    CoreError::Transport(TransportError::Network(format!("push decode: {e}")))
                });
            }

            // Non-2xx response — decide retry vs terminal.
            if is_retryable_status(code) && policy.should_retry(attempt) == RetryDecision::Retry {
                let retry_after = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|h| h.to_str().ok())
                    .and_then(parse_retry_after);
                let body = resp.text().await.unwrap_or_default();
                last_status = code;
                last_message = body;
                sleep_jittered(&policy, attempt, retry_after, &mut rng).await;
                attempt += 1;
                continue;
            }

            // Either non-retryable or retry budget exhausted.
            let body = resp.text().await.unwrap_or_default();
            if is_retryable_status(code) {
                // Budget exhausted on a retryable status — surface as RetryExhausted.
                return Err(CoreError::Transport(TransportError::RetryExhausted {
                    attempts: attempt + 1,
                    last_status: code,
                    last_message: body,
                }));
            }
            return Err(map_push_status(code, &body));
        }
    }

    /// POST an ack request with bounded retry on transient failures. See
    /// [`Self::push_with_retry`] for retry semantics.
    pub async fn ack_with_retry(
        &self,
        req: &AckRequest,
        policy: RetryPolicy,
    ) -> Result<(), CoreError> {
        self.ack_with_retry_rng(req, policy, rand_unit).await
    }

    /// Test-friendly variant of [`Self::ack_with_retry`].
    pub async fn ack_with_retry_rng<R>(
        &self,
        req: &AckRequest,
        policy: RetryPolicy,
        mut rng: R,
    ) -> Result<(), CoreError>
    where
        R: FnMut() -> f64,
    {
        let url = format!("{}/sync/ack", self.server_url);
        let mut attempt: u32 = 0;
        // last_status / last_message track the most recent transient failure so
        // that, if the retry budget is exhausted, the surfaced `RetryExhausted`
        // error carries actionable diagnostics. On a successful retry the
        // values are simply overwritten — that's the expected lifecycle, hence
        // the lint suppression below.
        #[allow(unused_assignments)]
        let mut last_status: u16 = 0;
        #[allow(unused_assignments)]
        let mut last_message: String = String::new();

        loop {
            let send_result = self
                .client
                .post(&url)
                .header("Authorization", format!("Bearer {}", self.jwt))
                .header("X-NClaw-Sync-Version", "1")
                .json(req)
                .send()
                .await;
            let resp = match send_result {
                Ok(r) => r,
                Err(e) => {
                    last_status = 0;
                    last_message = format!("ack send: {e}");
                    if policy.should_retry(attempt) == RetryDecision::Retry {
                        sleep_jittered(&policy, attempt, None, &mut rng).await;
                        attempt += 1;
                        continue;
                    }
                    return Err(CoreError::Transport(TransportError::RetryExhausted {
                        attempts: attempt + 1,
                        last_status,
                        last_message,
                    }));
                }
            };
            let status = resp.status();
            let code = status.as_u16();
            if status.is_success() {
                return Ok(());
            }
            if is_retryable_status(code) && policy.should_retry(attempt) == RetryDecision::Retry {
                let retry_after = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|h| h.to_str().ok())
                    .and_then(parse_retry_after);
                let body = resp.text().await.unwrap_or_default();
                last_status = code;
                last_message = body;
                sleep_jittered(&policy, attempt, retry_after, &mut rng).await;
                attempt += 1;
                continue;
            }
            let body = resp.text().await.unwrap_or_default();
            if is_retryable_status(code) {
                return Err(CoreError::Transport(TransportError::RetryExhausted {
                    attempts: attempt + 1,
                    last_status: code,
                    last_message: body,
                }));
            }
            return Err(CoreError::Transport(TransportError::Network(format!(
                "ack http {code}: {body}"
            ))));
        }
    }

    /// POST a snapshot request with bounded retry on transient failures.
    pub async fn snapshot_with_retry(
        &self,
        req: &SnapshotRequest,
        policy: RetryPolicy,
    ) -> Result<SnapshotResponse, CoreError> {
        self.snapshot_with_retry_rng(req, policy, rand_unit).await
    }

    /// Test-friendly variant of [`Self::snapshot_with_retry`].
    pub async fn snapshot_with_retry_rng<R>(
        &self,
        req: &SnapshotRequest,
        policy: RetryPolicy,
        mut rng: R,
    ) -> Result<SnapshotResponse, CoreError>
    where
        R: FnMut() -> f64,
    {
        let url = format!("{}/sync/snapshot", self.server_url);
        let mut attempt: u32 = 0;
        // last_status / last_message track the most recent transient failure so
        // that, if the retry budget is exhausted, the surfaced `RetryExhausted`
        // error carries actionable diagnostics. On a successful retry the
        // values are simply overwritten — that's the expected lifecycle, hence
        // the lint suppression below.
        #[allow(unused_assignments)]
        let mut last_status: u16 = 0;
        #[allow(unused_assignments)]
        let mut last_message: String = String::new();
        loop {
            let send_result = self
                .client
                .post(&url)
                .header("Authorization", format!("Bearer {}", self.jwt))
                .header("X-NClaw-Sync-Version", "1")
                .json(req)
                .send()
                .await;
            let resp = match send_result {
                Ok(r) => r,
                Err(e) => {
                    last_status = 0;
                    last_message = format!("snapshot send: {e}");
                    if policy.should_retry(attempt) == RetryDecision::Retry {
                        sleep_jittered(&policy, attempt, None, &mut rng).await;
                        attempt += 1;
                        continue;
                    }
                    return Err(CoreError::Transport(TransportError::RetryExhausted {
                        attempts: attempt + 1,
                        last_status,
                        last_message,
                    }));
                }
            };
            let status = resp.status();
            let code = status.as_u16();
            if status.is_success() {
                return resp.json::<SnapshotResponse>().await.map_err(|e| {
                    CoreError::Transport(TransportError::Network(format!(
                        "snapshot decode: {e}"
                    )))
                });
            }
            if is_retryable_status(code) && policy.should_retry(attempt) == RetryDecision::Retry {
                let retry_after = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|h| h.to_str().ok())
                    .and_then(parse_retry_after);
                let body = resp.text().await.unwrap_or_default();
                last_status = code;
                last_message = body;
                sleep_jittered(&policy, attempt, retry_after, &mut rng).await;
                attempt += 1;
                continue;
            }
            let body = resp.text().await.unwrap_or_default();
            if is_retryable_status(code) {
                return Err(CoreError::Transport(TransportError::RetryExhausted {
                    attempts: attempt + 1,
                    last_status: code,
                    last_message: body,
                }));
            }
            return Err(CoreError::Transport(TransportError::Network(format!(
                "snapshot http {code}: {body}"
            ))));
        }
    }
}

/// Sleep for `policy`'s jittered backoff, honoring an optional server
/// `Retry-After` hint. Pulled out for reuse across push/ack/snapshot.
async fn sleep_jittered<R: FnMut() -> f64>(
    policy: &RetryPolicy,
    attempt: u32,
    retry_after: Option<Duration>,
    rng: &mut R,
) {
    let computed = policy.jittered_delay(attempt, rng());
    let merged = policy.merge_retry_after(computed, retry_after);
    if merged > Duration::ZERO {
        tokio::time::sleep(merged).await;
    }
}

/// Map a non-success HTTP status from `/sync/push` into the typed error variant
/// the rest of the sync stack reasons about. See [`SyncNetwork::push`] for the
/// full table. The decoded body is included in the message for diagnostics —
/// the server returns a small `{"error":"...","status":N}` JSON envelope on
/// every non-2xx path (`writeJSONError` in `main.go`).
fn map_push_status(code: u16, body: &str) -> CoreError {
    let snippet = if body.is_empty() {
        String::new()
    } else {
        // Bound the body in the error to avoid huge messages.
        let trimmed = body.trim();
        let truncated: String = trimmed.chars().take(256).collect();
        format!(": {truncated}")
    };
    match code {
        400 | 413 => CoreError::Transport(TransportError::ProtocolViolation(format!(
            "push http {code}{snippet}"
        ))),
        401 => CoreError::Transport(TransportError::ProtocolViolation(format!(
            "push http 401 unauthorized{snippet}"
        ))),
        403 => CoreError::Sync(SyncError::InvalidState(format!(
            "push http 403 forbidden{snippet}"
        ))),
        500..=599 => CoreError::Transport(TransportError::Network(format!(
            "push http {code}{snippet}"
        ))),
        _ => CoreError::Transport(TransportError::Network(format!(
            "push http {code}{snippet}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_network_new_stores_credentials() {
        let client = SyncNetwork::new("http://localhost:8080", "test_jwt_token");
        assert_eq!(client.server_url, "http://localhost:8080");
        assert_eq!(client.jwt, "test_jwt_token");
    }

    #[test]
    fn subscribe_url_converts_http_to_ws_without_token() {
        let client = SyncNetwork::new("http://localhost:8080", "test_jwt");
        let url = client.subscribe_url();
        assert!(url.starts_with("ws://"));
        assert_eq!(url, "ws://localhost:8080/sync/subscribe");
        // V04-F04: token MUST NOT appear in the URL anywhere.
        assert!(!url.contains("test_jwt"));
        assert!(!url.contains("token"));
        assert!(!url.contains('?'));
    }

    #[test]
    fn subscribe_url_converts_https_to_wss_without_token() {
        let client = SyncNetwork::new("https://api.example.com", "test_jwt");
        let url = client.subscribe_url();
        assert!(url.starts_with("wss://"));
        assert_eq!(url, "wss://api.example.com/sync/subscribe");
        assert!(!url.contains("test_jwt"));
        assert!(!url.contains("token"));
        assert!(!url.contains('?'));
    }

    #[test]
    fn auth_frame_serializes_to_canonical_wire_format() {
        let client = SyncNetwork::new("https://api.example.com", "abc.def.ghi");
        let frame = client.auth_frame();
        assert_eq!(frame.kind, "auth");
        assert_eq!(frame.token, "abc.def.ghi");
        let json = frame.to_json();
        // Match server expectation byte-for-byte.
        assert_eq!(json, r#"{"type":"auth","token":"abc.def.ghi"}"#);
    }

    #[test]
    fn auth_frame_roundtrips_through_serde() {
        let frame = AuthFrame::new("jwt-value");
        let json = frame.to_json();
        let decoded: AuthFrame = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, frame);
    }

    #[test]
    fn push_request_serializes() {
        let client = SyncNetwork::new("http://localhost:8080", "test_jwt");
        let req = PushRequest {
            device_id: uuid::Uuid::nil(),
            events: vec![],
            cursor: None,
            schema_version: None,
        };
        let json = client.push_request(&req);
        assert!(json.contains("events"));
        assert!(json.contains("device_id"));
        // Optional cursor + schema_version are skipped when None.
        assert!(!json.contains("cursor"));
        assert!(!json.contains("schema_version"));
    }

    #[test]
    fn push_response_distinguishes_rejected_from_accepted() {
        let accepted = PushResult {
            event_id: uuid::Uuid::nil(),
            status: "accepted".to_string(),
            reason: None,
        };
        let duplicate = PushResult {
            event_id: uuid::Uuid::from_bytes([1; 16]),
            status: "duplicate".to_string(),
            reason: None,
        };
        let rejected = PushResult {
            event_id: uuid::Uuid::from_bytes([2; 16]),
            status: "rejected".to_string(),
            reason: Some("invalid signature".to_string()),
        };
        let resp = PushResponse {
            results: vec![accepted, duplicate, rejected.clone()],
            acks: vec![uuid::Uuid::nil(), uuid::Uuid::from_bytes([1; 16])],
        };
        assert!(!resp.all_accepted());
        let rej: Vec<&PushResult> = resp.rejected().collect();
        assert_eq!(rej.len(), 1);
        assert_eq!(rej[0], &rejected);
    }

    #[test]
    fn map_push_status_400_is_protocol_violation() {
        match map_push_status(400, r#"{"error":"invalid body","status":400}"#) {
            CoreError::Transport(TransportError::ProtocolViolation(m)) => {
                assert!(m.contains("400"), "msg: {m}");
            }
            other => panic!("expected ProtocolViolation, got {other:?}"),
        }
    }

    #[test]
    fn map_push_status_401_is_protocol_violation_unauthorized() {
        match map_push_status(401, r#"{"error":"invalid token","status":401}"#) {
            CoreError::Transport(TransportError::ProtocolViolation(m)) => {
                assert!(m.contains("401"));
                assert!(m.contains("unauthorized"));
            }
            other => panic!("expected ProtocolViolation, got {other:?}"),
        }
    }

    #[test]
    fn map_push_status_403_is_sync_invalid_state() {
        match map_push_status(403, r#"{"error":"device_id does not match token","status":403}"#) {
            CoreError::Sync(SyncError::InvalidState(m)) => {
                assert!(m.contains("403"));
                assert!(m.contains("forbidden"));
            }
            other => panic!("expected SyncError::InvalidState, got {other:?}"),
        }
    }

    #[test]
    fn map_push_status_413_is_protocol_violation() {
        match map_push_status(413, "") {
            CoreError::Transport(TransportError::ProtocolViolation(m)) => {
                assert!(m.contains("413"));
            }
            other => panic!("expected ProtocolViolation, got {other:?}"),
        }
    }

    #[test]
    fn map_push_status_500_is_network() {
        match map_push_status(500, "internal error") {
            CoreError::Transport(TransportError::Network(m)) => {
                assert!(m.contains("500"));
            }
            other => panic!("expected Network, got {other:?}"),
        }
    }

    #[test]
    fn pull_request_includes_filters() {
        let client = SyncNetwork::new("http://localhost:8080", "test_jwt");
        let req = PullRequest {
            since_hlc_wall_ms: 1000,
            since_hlc_lamport: 5,
            entity_filters: vec!["User".to_string(), "Message".to_string()],
            limit: 100,
        };
        let json = client.pull_request(&req);
        assert!(json.contains("User"));
        assert!(json.contains("since_hlc_wall_ms"));
    }
}
