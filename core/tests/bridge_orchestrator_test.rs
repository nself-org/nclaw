//! Integration tests for the bridge orchestrator failover chain.
//!
//! Tests the full orchestrator flow: Router::route → Transport dispatch → failover
//! from cloud (ServerMux/Frontier) to local on network failure.

use async_trait::async_trait;
use nclaw_core::bridge::orchestrator::Orchestrator;
use nclaw_core::bridge::router::{
    BridgeContext, ConnectionState, Privacy, PromptClass, PromptRequest, RouteOverride, UserPolicy,
};
use nclaw_core::bridge::transport::{Transport, TransportRequest, TransportResponse};
use nclaw_core::error::CoreError;
use nclaw_core::tier::Tier;
use std::sync::Arc;

/// Mock transport for testing.
struct MockTransport {
    name: String,
    should_fail: bool,
}

#[async_trait]
impl Transport for MockTransport {
    async fn execute(&self, req: &TransportRequest) -> Result<TransportResponse, CoreError> {
        if self.should_fail {
            return Err(CoreError::Other(format!("mock failure from {}", self.name)));
        }
        Ok(TransportResponse {
            text: format!("response from {}", self.name),
            tokens_used: 42,
            latency_ms: 100,
            source: self.name.clone(),
        })
    }

    fn name(&self) -> &'static str {
        "mock"
    }
}

fn make_prompt() -> PromptRequest {
    PromptRequest {
        prompt: "test prompt".into(),
        estimated_input_tokens: 5,
        estimated_output_tokens: 100,
        class: PromptClass::Chat,
        privacy: Privacy::Default,
        conversation_id: "test-conv".into(),
    }
}

fn make_context() -> BridgeContext {
    BridgeContext {
        local_tier: Tier::T1,
        connection_state: ConnectionState::Online,
        latency_budget_ms: 1000,
        cost_budget_usd: 10.0,
        server_mux_endpoint: Some("http://localhost:8080".into()),
        frontier_providers_available: vec!["anthropic".into()],
        user_policy: UserPolicy {
            prefer_local: false,
            max_cost_per_prompt_usd: 1.0,
            default_provider: None,
        },
        per_conversation_override: None,
    }
}

#[tokio::test]
async fn test_orchestrator_servermux_success() {
    let orch = Orchestrator {
        local: Arc::new(MockTransport {
            name: "local".into(),
            should_fail: false,
        }),
        server_mux: Some(Arc::new(MockTransport {
            name: "servermux".into(),
            should_fail: false,
        })),
        frontier: None,
    };

    let prompt = make_prompt();
    let ctx = make_context();
    let result = orch.run(&prompt, &ctx).await;

    assert!(result.is_ok());
    let resp = result.unwrap();
    assert!(resp.source.contains("servermux"));
}

#[tokio::test]
async fn test_orchestrator_servermux_fails_fallback_to_local() {
    let orch = Orchestrator {
        local: Arc::new(MockTransport {
            name: "local".into(),
            should_fail: false,
        }),
        server_mux: Some(Arc::new(MockTransport {
            name: "servermux".into(),
            should_fail: true,
        })),
        frontier: None,
    };

    let prompt = make_prompt();
    let ctx = make_context();
    let result = orch.run(&prompt, &ctx).await;

    assert!(result.is_ok());
    let resp = result.unwrap();
    assert!(resp.source.contains("local"), "should fallback to local");
}

#[tokio::test]
async fn test_orchestrator_local_failure_no_fallback() {
    let orch = Orchestrator {
        local: Arc::new(MockTransport {
            name: "local".into(),
            should_fail: true,
        }),
        server_mux: Some(Arc::new(MockTransport {
            name: "servermux".into(),
            should_fail: false,
        })),
        frontier: None,
    };

    let prompt = make_prompt();
    let mut ctx = make_context();
    ctx.user_policy.prefer_local = true; // Force local route

    let result = orch.run(&prompt, &ctx).await;

    assert!(result.is_err(), "local failure should not fallback");
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("mock failure from local"));
}

#[tokio::test]
async fn test_orchestrator_offline_routes_to_local() {
    let orch = Orchestrator {
        local: Arc::new(MockTransport {
            name: "local".into(),
            should_fail: false,
        }),
        server_mux: Some(Arc::new(MockTransport {
            name: "servermux".into(),
            should_fail: false,
        })),
        frontier: None,
    };

    let prompt = make_prompt();
    let mut ctx = make_context();
    ctx.connection_state = ConnectionState::Offline;

    let result = orch.run(&prompt, &ctx).await;

    assert!(result.is_ok());
    let resp = result.unwrap();
    assert!(resp.source.contains("local"));
}

#[tokio::test]
async fn test_orchestrator_frontier_unavailable_error() {
    let orch = Orchestrator {
        local: Arc::new(MockTransport {
            name: "local".into(),
            should_fail: false,
        }),
        server_mux: None,
        frontier: None,
    };

    let prompt = PromptRequest {
        prompt: "write code".into(),
        estimated_input_tokens: 10,
        estimated_output_tokens: 500,
        class: PromptClass::Code,
        privacy: Privacy::AllowFrontier,
        conversation_id: "test".into(),
    };

    let ctx = BridgeContext {
        local_tier: Tier::T1,
        connection_state: ConnectionState::Online,
        latency_budget_ms: 2000,
        cost_budget_usd: 0.05,
        server_mux_endpoint: None,
        frontier_providers_available: vec!["anthropic".into()],
        user_policy: UserPolicy {
            prefer_local: false,
            max_cost_per_prompt_usd: 0.1,
            default_provider: Some("anthropic".into()),
        },
        per_conversation_override: None,
    };

    let result = orch.run(&prompt, &ctx).await;

    // Router will try frontier, dispatch will fail with "not configured"
    assert!(result.is_err());
}

#[tokio::test]
async fn test_orchestrator_no_transport_configured() {
    let orch = Orchestrator {
        local: Arc::new(MockTransport {
            name: "local".into(),
            should_fail: false,
        }),
        server_mux: None,
        frontier: None,
    };

    let prompt = make_prompt();
    let ctx = make_context();

    let result = orch.run(&prompt, &ctx).await;

    // Router will route to ServerMux (online, default privacy, no override),
    // dispatch fails with "not configured", then fallback to local succeeds
    assert!(result.is_ok());
    let resp = result.unwrap();
    assert!(resp.source.contains("local"));
}
