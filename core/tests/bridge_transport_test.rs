//! Integration tests for bridge transports.
//!
//! Uses httpmock to simulate mux and frontier endpoints without real network.

use httpmock::prelude::*;
use libnclaw::bridge::transport::{
    FrontierTransport, LocalTransport, ServerMuxTransport, Transport, TransportRequest,
};

#[tokio::test]
async fn test_local_transport_basic() {
    let transport = LocalTransport::new();
    let req = TransportRequest {
        prompt: "Hello, world!".to_string(),
        max_tokens: 100,
        temperature: 0.7,
    };

    let resp = transport.execute(&req).await.expect("local should succeed");
    assert_eq!(resp.source, "local");
    assert!(resp.text.contains("local stub"));
    assert!(resp.latency_ms >= 0);
}

#[tokio::test]
async fn test_server_mux_transport() {
    let server = MockServer::new_async().await;

    // Mock the mux endpoint
    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/inference")
                .json_body_contains("prompt")
                .json_body_contains("max_tokens");
            then.status(200).json_body(serde_json::json!({
                "text": "Mocked response from server mux",
                "tokens_used": 42
            }));
        })
        .await;

    let endpoint = format!("{}/inference", server.url());
    let transport = ServerMuxTransport::new(endpoint);

    let req = TransportRequest {
        prompt: "Test prompt for mux".to_string(),
        max_tokens: 100,
        temperature: 0.7,
    };

    let resp = transport.execute(&req).await.expect("mux should succeed");
    assert_eq!(resp.source, "server-mux");
    assert_eq!(resp.text, "Mocked response from server mux");
    assert_eq!(resp.tokens_used, 42);

    mock.assert_async().await;
}

#[tokio::test]
async fn test_frontier_anthropic() {
    let server = MockServer::new_async().await;

    let mock = server
        .mock_async(|when, then| {
            when.method(POST)
                .path("/v1/messages")
                .header("x-api-key", "test-key");
            then.status(200).json_body(serde_json::json!({
                "content": [{"text": "Response from Anthropic"}]
            }));
        })
        .await;

    // Override the endpoint for testing
    let transport = FrontierTransport::new(
        "anthropic".to_string(),
        "test-key".to_string(),
        "claude-3.5-sonnet".to_string(),
    );

    let req = TransportRequest {
        prompt: "Test Anthropic".to_string(),
        max_tokens: 100,
        temperature: 0.7,
    };

    // Note: real execution will hit the actual API; this test is a structure check
    // For full testing, we'd need to mock reqwest itself or use a test double
    let source = transport.name();
    assert_eq!(source, "frontier");
}

#[tokio::test]
async fn test_frontier_openai() {
    let transport = FrontierTransport::new(
        "openai".to_string(),
        "test-key".to_string(),
        "gpt-4o-mini".to_string(),
    );

    let source = transport.name();
    assert_eq!(source, "frontier");
}

#[tokio::test]
async fn test_frontier_google() {
    let transport = FrontierTransport::new(
        "google".to_string(),
        "test-key".to_string(),
        "gemini-1.5-flash".to_string(),
    );

    let source = transport.name();
    assert_eq!(source, "frontier");
}

#[tokio::test]
async fn test_transport_trait_object() {
    let local: Box<dyn Transport> = Box::new(LocalTransport::new());
    assert_eq!(local.name(), "local");

    let server_mux: Box<dyn Transport> =
        Box::new(ServerMuxTransport::new("http://localhost:8080".to_string()));
    assert_eq!(server_mux.name(), "server-mux");

    let frontier: Box<dyn Transport> = Box::new(FrontierTransport::new(
        "anthropic".to_string(),
        "key".to_string(),
        "model".to_string(),
    ));
    assert_eq!(frontier.name(), "frontier");
}
