//! Bridge transports — execute RouteDecision to generate LLM responses.
//!
//! Each transport variant (Local, ServerMux, Frontier) wraps a concrete backend
//! and implements the Transport trait for pluggable execution.
//!
//! Decision #11 routing produces a RouteDecision; these transports execute it.

pub mod frontier;
pub mod local;
pub mod server_mux;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::error::CoreError;

/// Request payload for any transport.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransportRequest {
    pub prompt: String,
    pub max_tokens: u32,
    pub temperature: f32,
}

/// Response from any transport execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransportResponse {
    /// Generated text.
    pub text: String,
    /// Tokens consumed (if known).
    pub tokens_used: u32,
    /// Latency in milliseconds.
    pub latency_ms: u64,
    /// Which transport produced this response.
    pub source: String,
}

/// Pluggable transport interface.
#[async_trait]
pub trait Transport: Send + Sync {
    /// Execute the request, returning a response or error.
    async fn execute(&self, req: &TransportRequest) -> Result<TransportResponse, CoreError>;
    /// Transport name for telemetry / debugging.
    fn name(&self) -> &'static str;
}
