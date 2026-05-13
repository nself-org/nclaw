//! Streaming token generation with backpressure and cancellation.
//!
//! `StreamingGenerator` wraps any `LlmBackend`, drives token-by-token delivery over
//! an `mpsc` channel, and honours cancellation via `CancellationToken`.

use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

// ============================================================================
// Public types
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TokenEvent {
    Token { text: String, id: u32 },
    Done { stats: GenerateStats, cancelled: bool },
    Error { kind: String, message: String },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GenerateStats {
    pub total_tokens: u32,
    pub elapsed_ms: u64,
    pub tokens_per_second: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerateParams {
    pub max_tokens: u32,
    pub temperature: f32,
    pub top_p: f32,
    pub top_k: u32,
    pub repeat_penalty: f32,
    pub stop_sequences: Vec<String>,
}

impl Default for GenerateParams {
    fn default() -> Self {
        Self {
            max_tokens: 1024,
            temperature: 0.7,
            top_p: 0.95,
            top_k: 40,
            repeat_penalty: 1.1,
            stop_sequences: vec![],
        }
    }
}

// ============================================================================
// StreamingGenerator
// ============================================================================

pub struct StreamingGenerator {
    pub channel_capacity: usize,
    /// How long (ms) to block on a full channel before emitting a backpressure error.
    pub backpressure_block_ms: u64,
}

impl Default for StreamingGenerator {
    fn default() -> Self {
        Self::new()
    }
}

impl StreamingGenerator {
    pub fn new() -> Self {
        Self {
            channel_capacity: 32,
            backpressure_block_ms: 500,
        }
    }

    /// Spawn generation on a dedicated tokio task; consumer drains via the returned receiver.
    ///
    /// Drives streaming by calling `backend.generate()` and iterating the returned token vec
    /// one token at a time — adapts the batch `LlmBackend` to a streaming event sequence.
    ///
    /// Cancellation: when `cancel.is_cancelled()` the producer stops at the next token
    /// boundary, sends `Done { cancelled: true, stats }`, and exits cleanly.
    pub fn spawn<B>(
        &self,
        backend: Arc<B>,
        prompt: String,
        params: GenerateParams,
        cancel: CancellationToken,
    ) -> mpsc::Receiver<TokenEvent>
    where
        B: crate::backend::LlmBackend + Send + Sync + 'static,
    {
        let (tx, rx) = mpsc::channel(self.channel_capacity);
        let block_ms = self.backpressure_block_ms;

        tokio::spawn(async move {
            let start = tokio::time::Instant::now();
            let mut total_tokens: u32 = 0;

            // Translate GenerateParams → GenOpts for the existing trait.
            let opts = crate::backend::GenOpts {
                model: "default".into(),
                max_tokens: params.max_tokens as usize,
                temperature: params.temperature,
                top_p: params.top_p,
                stop_sequences: params.stop_sequences.clone(),
            };

            let token_list = match backend.generate(&prompt, opts).await {
                Ok(ts) => ts.tokens,
                Err(e) => {
                    let _ = tx
                        .send(TokenEvent::Error {
                            kind: "backend".into(),
                            message: e.to_string(),
                        })
                        .await;
                    return;
                }
            };

            // Stream tokens one-by-one, honouring cancel + backpressure.
            for raw_text in token_list {
                if cancel.is_cancelled() {
                    let stats = make_stats(total_tokens, start.elapsed());
                    let _ = tx.send(TokenEvent::Done { stats, cancelled: true }).await;
                    return;
                }

                total_tokens += 1;
                let event = TokenEvent::Token {
                    text: raw_text,
                    id: total_tokens,
                };

                let deadline = std::time::Duration::from_millis(block_ms);
                if tokio::time::timeout(deadline, tx.send(event))
                    .await
                    .is_err()
                {
                    // Receiver dropped or consumer lagged past the deadline.
                    let _ = tx
                        .send(TokenEvent::Error {
                            kind: "backpressure".into(),
                            message: format!("consumer lagged > {}ms", block_ms),
                        })
                        .await;
                    return;
                }
            }

            let stats = make_stats(total_tokens, start.elapsed());
            let _ = tx.send(TokenEvent::Done { stats, cancelled: false }).await;
        });

        rx
    }
}

// ============================================================================
// Helpers
// ============================================================================

fn make_stats(tokens: u32, dur: std::time::Duration) -> GenerateStats {
    GenerateStats {
        total_tokens: tokens,
        elapsed_ms: dur.as_millis() as u64,
        tokens_per_second: ratio(tokens, dur),
    }
}

fn ratio(tokens: u32, dur: std::time::Duration) -> f64 {
    if dur.is_zero() {
        return 0.0;
    }
    tokens as f64 / dur.as_secs_f64()
}
