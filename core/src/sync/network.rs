//! Network push/pull/subscribe wrappers for sync protocol.
//!
//! HTTP endpoints for pushing local changes and pulling remote changes,
//! plus WebSocket subscription URL generation for real-time sync.

use crate::error::CoreError;
use crate::sync::lww::EventEnvelope;
use serde::{Deserialize, Serialize};

/// Request payload for pushing events to the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushRequest {
    pub events: Vec<EventEnvelope>,
}

/// Acknowledgment of a single pushed event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventAck {
    pub event_id: uuid::Uuid,
    pub status: String,
}

/// Response from a push operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushResponse {
    pub acks: Vec<EventAck>,
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

/// Sync network client for push/pull/subscribe operations.
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

    /// Push local events to the server (caller must wrap in async/tokio spawn).
    /// Returns a JSON request body ready for posting to `{server_url}/sync/push`.
    pub fn push_request(&self, req: &PushRequest) -> String {
        serde_json::to_string(req).unwrap_or_else(|_| "{}".to_string())
    }

    /// Pull remote events from the server (caller must wrap in async/tokio spawn).
    /// Returns a JSON request body ready for posting to `{server_url}/sync/pull`.
    pub fn pull_request(&self, req: &PullRequest) -> String {
        serde_json::to_string(req).unwrap_or_else(|_| "{}".to_string())
    }

    /// Generate a WebSocket subscription URL for real-time sync updates.
    ///
    /// The caller is responsible for establishing the WebSocket connection
    /// and handling incoming events in a tokio::spawn task.
    pub fn subscribe_url(&self) -> String {
        let s = self
            .server_url
            .replacen("http://", "ws://", 1)
            .replacen("https://", "wss://", 1);
        format!("{}/sync/subscribe?token={}", s, self.jwt)
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
    fn subscribe_url_converts_http_to_ws() {
        let client = SyncNetwork::new("http://localhost:8080", "test_jwt");
        let url = client.subscribe_url();
        assert!(url.starts_with("ws://"));
        assert!(url.contains("/sync/subscribe?token=test_jwt"));
    }

    #[test]
    fn subscribe_url_converts_https_to_wss() {
        let client = SyncNetwork::new("https://api.example.com", "test_jwt");
        let url = client.subscribe_url();
        assert!(url.starts_with("wss://"));
        assert!(url.contains("/sync/subscribe?token=test_jwt"));
    }

    #[test]
    fn push_request_serializes() {
        let client = SyncNetwork::new("http://localhost:8080", "test_jwt");
        let req = PushRequest { events: vec![] };
        let json = client.push_request(&req);
        assert!(json.contains("events"));
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
