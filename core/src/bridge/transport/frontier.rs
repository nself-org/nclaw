//! Direct frontier transport — calls Anthropic, OpenAI, or Google APIs directly.
//!
//! Handles provider-specific request/response formatting for Anthropic,
//! OpenAI, and Google Generative AI models.

use async_trait::async_trait;
use std::time::Instant;

use super::{Transport, TransportRequest, TransportResponse};
use crate::error::CoreError;

/// Direct frontier API transport.
#[derive(Clone)]
pub struct FrontierTransport {
    /// Provider name: "anthropic" | "openai" | "google"
    pub provider: String,
    pub api_key: String,
    pub model_id: String,
    client: reqwest::Client,
}

impl FrontierTransport {
    pub fn new(provider: String, api_key: String, model_id: String) -> Self {
        Self {
            provider,
            api_key,
            model_id,
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl Transport for FrontierTransport {
    async fn execute(&self, req: &TransportRequest) -> Result<TransportResponse, CoreError> {
        let start = Instant::now();

        match self.provider.as_str() {
            "anthropic" => self.call_anthropic(req, start).await,
            "openai" => self.call_openai(req, start).await,
            "google" => self.call_google(req, start).await,
            other => Err(CoreError::Other(format!("unknown provider: {}", other))),
        }
    }

    fn name(&self) -> &'static str {
        "frontier"
    }
}

impl FrontierTransport {
    async fn call_anthropic(
        &self,
        req: &TransportRequest,
        start: Instant,
    ) -> Result<TransportResponse, CoreError> {
        let body = serde_json::json!({
            "model": self.model_id,
            "max_tokens": req.max_tokens,
            "messages": [{"role": "user", "content": req.prompt}]
        });

        let resp = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .json(&body)
            .send()
            .await
            .map_err(|e| CoreError::Other(format!("anthropic request failed: {}", e)))?;

        if !resp.status().is_success() {
            return Err(CoreError::Other(format!(
                "anthropic error: {}",
                resp.status()
            )));
        }

        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| CoreError::Other(format!("anthropic response parse failed: {}", e)))?;

        let text = v
            .pointer("/content/0/text")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();

        Ok(TransportResponse {
            text,
            tokens_used: 0,
            latency_ms: start.elapsed().as_millis() as u64,
            source: "frontier:anthropic".into(),
        })
    }

    async fn call_openai(
        &self,
        req: &TransportRequest,
        start: Instant,
    ) -> Result<TransportResponse, CoreError> {
        let body = serde_json::json!({
            "model": self.model_id,
            "max_tokens": req.max_tokens,
            "messages": [{"role": "user", "content": req.prompt}]
        });

        let resp = self
            .client
            .post("https://api.openai.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .json(&body)
            .send()
            .await
            .map_err(|e| CoreError::Other(format!("openai request failed: {}", e)))?;

        if !resp.status().is_success() {
            return Err(CoreError::Other(format!("openai error: {}", resp.status())));
        }

        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| CoreError::Other(format!("openai response parse failed: {}", e)))?;

        let text = v
            .pointer("/choices/0/message/content")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();

        Ok(TransportResponse {
            text,
            tokens_used: 0,
            latency_ms: start.elapsed().as_millis() as u64,
            source: "frontier:openai".into(),
        })
    }

    async fn call_google(
        &self,
        req: &TransportRequest,
        start: Instant,
    ) -> Result<TransportResponse, CoreError> {
        let body = serde_json::json!({
            "contents": [{"parts": [{"text": req.prompt}]}]
        });

        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}",
            self.model_id, self.api_key
        );

        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .map_err(|e| CoreError::Other(format!("google request failed: {}", e)))?;

        if !resp.status().is_success() {
            return Err(CoreError::Other(format!("google error: {}", resp.status())));
        }

        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| CoreError::Other(format!("google response parse failed: {}", e)))?;

        let text = v
            .pointer("/candidates/0/content/parts/0/text")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();

        Ok(TransportResponse {
            text,
            tokens_used: 0,
            latency_ms: start.elapsed().as_millis() as u64,
            source: "frontier:google".into(),
        })
    }
}
