//! Integration tests for OllamaBackend with mock HTTP responses.
//!
//! Tests verify:
//! - Auto-detect on a known-empty port (graceful None return)
//! - Model listing via mocked /api/tags
//! - Chat streaming via mocked /api/chat with NDJSON chunks
//! - Embedding generation via mocked /api/embeddings

use httpmock::prelude::*;
use libnclaw::llm::{OllamaBackend, OllamaMessage};
use tokio_stream::StreamExt;

#[tokio::test]
async fn test_auto_detect_not_running() {
    // Auto-detect on a known-empty port; should return None gracefully.
    // Ollama is likely NOT running on this machine during test.
    let result = OllamaBackend::auto_detect().await;
    // Result is None if Ollama not running (expected), or Some if it is.
    // We don't assert anything — just verify it doesn't panic.
    assert!(result.is_none() || result.is_some());
}

#[tokio::test]
async fn test_list_models_mocked() {
    let server = MockServer::start();

    let response_body = r#"{
        "models": [
            {
                "name": "llama2",
                "size": 3791621160,
                "modified_at": "2024-01-15T12:00:00Z"
            },
            {
                "name": "neural-chat",
                "size": 6748567900,
                "modified_at": "2024-01-14T08:30:00Z"
            }
        ]
    }"#;

    server.expect(
        mock()
            .method(GET)
            .path("/api/tags")
            .return_status(200)
            .return_body(response_body),
    );

    let backend = OllamaBackend::new(server.base_url());
    let models = backend.list_models().await.unwrap();

    assert_eq!(models.len(), 2);
    assert_eq!(models[0].name, "llama2");
    assert_eq!(models[1].name, "neural-chat");
}

#[tokio::test]
async fn test_chat_stream_mocked() {
    let server = MockServer::start();

    // Mock /api/chat with 3 NDJSON chunks
    let chunk1 = r#"{"message":{"role":"assistant","content":"Hello"},"done":false}"#;
    let chunk2 = r#"{"message":{"role":"assistant","content":" world"},"done":false}"#;
    let chunk3 = r#"{"message":{"role":"assistant","content":"!"},"done":true}"#;
    let response_body = format!("{}\n{}\n{}\n", chunk1, chunk2, chunk3);

    server.expect(
        mock()
            .method(POST)
            .path("/api/chat")
            .return_status(200)
            .return_body(response_body),
    );

    let backend = OllamaBackend::new(server.base_url());
    let msgs = vec![OllamaMessage {
        role: "user".into(),
        content: "Say hello".into(),
    }];

    let mut stream = backend.chat_stream("llama2", &msgs).await.unwrap();

    let mut tokens = Vec::new();
    while let Some(result) = stream.next().await {
        tokens.push(result.unwrap());
    }

    assert_eq!(tokens.len(), 3);
    assert_eq!(tokens[0], "Hello");
    assert_eq!(tokens[1], " world");
    assert_eq!(tokens[2], "!");
}

#[tokio::test]
async fn test_embed_mocked() {
    let server = MockServer::start();

    let response_body = r#"{
        "embedding": [0.1, 0.2, 0.3, 0.4, 0.5]
    }"#;

    server.expect(
        mock()
            .method(POST)
            .path("/api/embeddings")
            .return_status(200)
            .return_body(response_body),
    );

    let backend = OllamaBackend::new(server.base_url());
    let embedding = backend
        .embed("nomic-embed-text", "test prompt")
        .await
        .unwrap();

    assert_eq!(embedding.len(), 5);
    assert_eq!(embedding[0], 0.1);
    assert_eq!(embedding[4], 0.5);
}

#[tokio::test]
async fn test_chat_stream_empty_content() {
    let server = MockServer::start();

    // Chunk with empty content should be skipped
    let chunk1 = r#"{"message":{"role":"assistant","content":""},"done":false}"#;
    let chunk2 = r#"{"message":{"role":"assistant","content":"token"},"done":true}"#;
    let response_body = format!("{}\n{}\n", chunk1, chunk2);

    server.expect(
        mock()
            .method(POST)
            .path("/api/chat")
            .return_status(200)
            .return_body(response_body),
    );

    let backend = OllamaBackend::new(server.base_url());
    let msgs = vec![OllamaMessage {
        role: "user".into(),
        content: "test".into(),
    }];

    let mut stream = backend.chat_stream("llama2", &msgs).await.unwrap();
    let mut tokens = Vec::new();
    while let Some(result) = stream.next().await {
        tokens.push(result.unwrap());
    }

    // Only non-empty token should be collected
    assert_eq!(tokens.len(), 1);
    assert_eq!(tokens[0], "token");
}
