//! Server mux transport — forwards requests to a user-configured mux endpoint.
//!
//! The mux plugin at the user's endpoint (e.g., plugins-pro/mux) receives the
//! request, selects a backend model, and returns the response.

use async_trait::async_trait;
use std::time::Instant;

use super::{Transport, TransportRequest, TransportResponse};
use crate::error::CoreError;

/// Server mux transport — HTTP POST to user's mux endpoint.
#[derive(Clone)]
pub struct ServerMuxTransport {
    pub endpoint: String,
    client: reqwest::Client,
}

impl ServerMuxTransport {
    pub fn new(endpoint: String) -> Self {
        Self {
            endpoint,
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl Transport for ServerMuxTransport {
    async fn execute(&self, req: &TransportRequest) -> Result<TransportResponse, CoreError> {
        let start = Instant::now();

        let body = serde_json::json!({
            "prompt": req.prompt,
            "max_tokens": req.max_tokens,
            "temperature": req.temperature,
        });

        let resp = self
            .client
            .post(&self.endpoint)
            .json(&body)
            .send()
            .await
            .map_err(|e| CoreError::Other(format!("mux request failed: {}", e)))?;

        if !resp.status().is_success() {
            return Err(CoreError::Other(format!("mux error: {}", resp.status())));
        }

        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| CoreError::Other(format!("mux response parse failed: {}", e)))?;

        let text = v
            .get("text")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();
        let tokens_used = v.get("tokens_used").and_then(|t| t.as_u64()).unwrap_or(0) as u32;

        Ok(TransportResponse {
            text,
            tokens_used,
            latency_ms: start.elapsed().as_millis() as u64,
            source: "server-mux".into(),
        })
    }

    fn name(&self) -> &'static str {
        "server-mux"
    }
}
