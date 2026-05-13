//! Integration tests for `StreamingGenerator` — backpressure + cancellation.
//!
//! Uses `InMemoryLlm` (fixture-based) so no real LLM binary is needed.

use libnclaw::llm::stream::{GenerateParams, StreamingGenerator, TokenEvent};
use libnclaw::testing::InMemoryLlm;
use std::sync::Arc;
use tokio_util::sync::CancellationToken;

// ============================================================================
// Test 1: Full generation — no cancel
// ============================================================================

#[tokio::test]
async fn test_stream_full_no_cancel() {
    let tokens: Vec<String> = (0..10).map(|i| format!("tok{}", i)).collect();
    let llm = Arc::new(
        InMemoryLlm::builder()
            .with_fixture("hello".into(), tokens.clone())
            .build(),
    );

    let gen = StreamingGenerator::new();
    let cancel = CancellationToken::new();
    let mut rx = gen.spawn(llm, "hello".into(), GenerateParams::default(), cancel);

    let mut received_tokens = 0u32;
    let mut done_seen = false;
    while let Some(event) = rx.recv().await {
        match event {
            TokenEvent::Token { id, .. } => {
                received_tokens += 1;
                assert_eq!(id, received_tokens, "token IDs must be sequential");
            }
            TokenEvent::Done { stats, cancelled } => {
                assert!(!cancelled, "should not be cancelled");
                assert_eq!(stats.total_tokens, 10);
                done_seen = true;
                break;
            }
            TokenEvent::Error { kind, message } => {
                panic!("unexpected error: kind={kind} message={message}");
            }
        }
    }
    assert_eq!(received_tokens, 10, "should receive exactly 10 tokens");
    assert!(done_seen, "Done event must arrive");
}

// ============================================================================
// Test 2: Cancel after 3 tokens
// ============================================================================

#[tokio::test]
async fn test_stream_cancel_mid_generation() {
    // 20 tokens so the cancel definitely fires before the end.
    let tokens: Vec<String> = (0..20).map(|i| format!("word{}", i)).collect();
    let llm = Arc::new(
        InMemoryLlm::builder()
            .with_fixture("prompt".into(), tokens)
            .build(),
    );

    let gen = StreamingGenerator::new();
    let cancel = CancellationToken::new();
    let mut rx = gen.spawn(
        llm,
        "prompt".into(),
        GenerateParams::default(),
        cancel.clone(),
    );

    let mut received_tokens = 0u32;
    let mut cancelled_seen = false;

    while let Some(event) = rx.recv().await {
        match event {
            TokenEvent::Token { .. } => {
                received_tokens += 1;
                if received_tokens == 3 {
                    cancel.cancel();
                }
            }
            TokenEvent::Done { stats, cancelled } => {
                if cancelled {
                    cancelled_seen = true;
                    // Allow a small window: the producer may have already queued
                    // tokens that arrived in-flight before the cancel check.
                    assert!(
                        stats.total_tokens >= 3 && stats.total_tokens <= 6,
                        "expected 3-6 tokens before cancel, got {}",
                        stats.total_tokens
                    );
                } else {
                    // Should not reach Done{cancelled:false} after cancel.
                    panic!("expected cancelled=true");
                }
                break;
            }
            TokenEvent::Error { kind, message } => {
                panic!("unexpected error: kind={kind} message={message}");
            }
        }
    }
    assert!(cancelled_seen, "Done{{cancelled:true}} must arrive");
    assert!(received_tokens >= 3, "must receive at least 3 tokens");
}

// ============================================================================
// Test 3: Backpressure — slow consumer triggers Error{kind:"backpressure"}
// ============================================================================

#[tokio::test]
async fn test_stream_backpressure_error() {
    // 30 tokens, channel_capacity=1, backpressure_block_ms=100.
    // Consumer sleeps 300ms between reads — well past the 100ms budget.
    let tokens: Vec<String> = (0..30).map(|i| format!("t{}", i)).collect();
    let llm = Arc::new(
        InMemoryLlm::builder()
            .with_fixture("slow".into(), tokens)
            .build(),
    );

    let mut gen = StreamingGenerator::new();
    gen.channel_capacity = 1;
    gen.backpressure_block_ms = 100;

    let cancel = CancellationToken::new();
    let mut rx = gen.spawn(llm, "slow".into(), GenerateParams::default(), cancel);

    let mut backpressure_hit = false;
    loop {
        // Simulate a slow consumer: sleep 300ms before each recv.
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        match rx.recv().await {
            None => break, // channel closed
            Some(TokenEvent::Error { kind, .. }) if kind == "backpressure" => {
                backpressure_hit = true;
                break;
            }
            Some(TokenEvent::Done { .. }) => break,
            Some(_) => {} // Token events while channel drains
        }
    }
    assert!(
        backpressure_hit,
        "backpressure Error must be emitted for slow consumers"
    );
}
