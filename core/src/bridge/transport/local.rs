//! Local transport — routes to llama.cpp backend for on-device inference.
//!
//! S19.T03 will integrate the real LlamaCppBackend; for now, this scaffold
//! returns canned responses suitable for integration testing.

use async_trait::async_trait;
use std::time::Instant;

use super::{Transport, TransportRequest, TransportResponse};
use crate::error::CoreError;

/// Local llama.cpp transport.
#[derive(Clone)]
pub struct LocalTransport {
    // S19.T03 will add: llama_backend: Arc<LlamaCppBackend>
}

impl LocalTransport {
    pub fn new() -> Self {
        Self {}
    }
}

impl Default for LocalTransport {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Transport for LocalTransport {
    async fn execute(&self, req: &TransportRequest) -> Result<TransportResponse, CoreError> {
        let start = Instant::now();

        // S19.T03 integration: forward to real LlamaCppBackend
        // For now, scaffold response for testing
        Ok(TransportResponse {
            text: format!(
                "(local stub) {}",
                req.prompt.chars().take(40).collect::<String>()
            ),
            tokens_used: (req.prompt.len() / 4) as u32,
            latency_ms: start.elapsed().as_millis() as u64,
            source: "local".into(),
        })
    }

    fn name(&self) -> &'static str {
        "local"
    }
}
