//! Bridge orchestrator — runs Router::route then dispatches via the matching Transport,
//! with offline failover from cloud → local.
//!
//! Composes the stateless Router (Decision #11) with pluggable Transport implementations,
//! adding resilience via failover: if the primary route fails and it's not Local, automatically
//! fall back to Local inference.

use crate::bridge::router::{BridgeContext, PromptRequest, RouteDecision, Router};
use crate::bridge::transport::{Transport, TransportRequest, TransportResponse};
use crate::error::CoreError;
use std::sync::Arc;

/// Bridge orchestrator — stateful executor that composes Router + Transport.
///
/// The orchestrator:
/// 1. Routes the prompt using the stateless `Router::route`.
/// 2. Dispatches to the appropriate transport (Local, ServerMux, or Frontier).
/// 3. On failure, automatically failover from cloud → local (unless already Local).
pub struct Orchestrator {
    /// Local transport — always available, fallback target.
    pub local: Arc<dyn Transport>,
    /// ServerMux transport — optional, routes via server endpoint.
    pub server_mux: Option<Arc<dyn Transport>>,
    /// Frontier transport — optional, routes via frontier API.
    pub frontier: Option<Arc<dyn Transport>>,
}

impl Orchestrator {
    /// Execute a prompt request with routing and failover.
    ///
    /// # Process
    /// 1. Call `Router::route` to determine the best route.
    /// 2. Dispatch via the appropriate transport.
    /// 3. On failure, failover to Local (if not already using Local).
    /// 4. If Local was the primary route and fails, return the error.
    ///
    /// # Errors
    /// - If the primary route succeeds, returns the transport response.
    /// - If the primary route fails and we failover to Local, returns the Local result.
    /// - If Local fails (either as primary or fallback), returns the Local error.
    pub async fn run(
        &self,
        prompt: &PromptRequest,
        ctx: &BridgeContext,
    ) -> Result<TransportResponse, CoreError> {
        let decision = Router::route(prompt, ctx);
        let req = TransportRequest {
            prompt: prompt.prompt.clone(),
            max_tokens: prompt.estimated_output_tokens.max(256),
            temperature: 0.7,
        };

        let primary_result = self.dispatch(&decision, &req).await;
        match primary_result {
            Ok(resp) => Ok(resp),
            Err(e) => {
                // Queue decision means "no eligible route" — propagate the error
                // rather than silently falling back to Local. Queue is a deliberate
                // routing outcome (e.g. user override that cannot be satisfied),
                // not a transport failure.
                if matches!(decision, RouteDecision::Queue { .. }) {
                    return Err(e);
                }
                // If primary route is not Local, attempt fallback to Local.
                if !matches!(decision, RouteDecision::Local { .. }) {
                    return self.local.execute(&req).await;
                }
                // Local was primary and failed — no fallback.
                Err(e)
            }
        }
    }

    /// Dispatch a request to the transport matching the decision.
    async fn dispatch(
        &self,
        decision: &RouteDecision,
        req: &TransportRequest,
    ) -> Result<TransportResponse, CoreError> {
        match decision {
            RouteDecision::Local { .. } => self.local.execute(req).await,
            RouteDecision::ServerMux { .. } => {
                self.server_mux
                    .as_ref()
                    .ok_or_else(|| CoreError::Other("server_mux transport not configured".into()))?
                    .execute(req)
                    .await
            }
            RouteDecision::DirectFrontier { .. } => {
                self.frontier
                    .as_ref()
                    .ok_or_else(|| CoreError::Other("frontier transport not configured".into()))?
                    .execute(req)
                    .await
            }
            RouteDecision::Queue { reason } => Err(CoreError::Other(format!("queued: {}", reason))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;

    /// Mock transport that always succeeds.
    struct AlwaysOkTransport(String);

    #[async_trait]
    impl Transport for AlwaysOkTransport {
        async fn execute(&self, req: &TransportRequest) -> Result<TransportResponse, CoreError> {
            Ok(TransportResponse {
                text: format!(
                    "ok from {}: {}",
                    self.0,
                    &req.prompt[..req.prompt.len().min(20)]
                ),
                tokens_used: 10,
                latency_ms: 1,
                source: self.0.clone(),
            })
        }

        fn name(&self) -> &'static str {
            "mock_ok"
        }
    }

    /// Mock transport that always fails.
    struct AlwaysErrTransport;

    #[async_trait]
    impl Transport for AlwaysErrTransport {
        async fn execute(&self, _req: &TransportRequest) -> Result<TransportResponse, CoreError> {
            Err(CoreError::Other("simulated failure".into()))
        }

        fn name(&self) -> &'static str {
            "mock_err"
        }
    }

    #[tokio::test]
    async fn test_online_servermux_default_privacy_routes_to_servermux() {
        let orchestrator = Orchestrator {
            local: Arc::new(AlwaysOkTransport("local".into())),
            server_mux: Some(Arc::new(AlwaysOkTransport("servermux".into()))),
            frontier: None,
        };

        let prompt = PromptRequest {
            prompt: "hello".into(),
            estimated_input_tokens: 5,
            estimated_output_tokens: 100,
            class: crate::bridge::router::PromptClass::Chat,
            privacy: crate::bridge::router::Privacy::Default,
            conversation_id: "test".into(),
        };

        let ctx = BridgeContext {
            local_tier: crate::tier::Tier::T1,
            connection_state: crate::bridge::router::ConnectionState::Online,
            latency_budget_ms: 1000,
            cost_budget_usd: 10.0,
            server_mux_endpoint: Some("http://localhost:8080".into()),
            frontier_providers_available: vec![],
            user_policy: crate::bridge::router::UserPolicy {
                prefer_local: false,
                max_cost_per_prompt_usd: 1.0,
                default_provider: None,
            },
            per_conversation_override: None,
        };

        let result = orchestrator.run(&prompt, &ctx).await;
        assert!(result.is_ok());
        let resp = result.unwrap();
        assert!(resp.source.contains("servermux"));
    }

    #[tokio::test]
    async fn test_servermux_failure_fails_over_to_local() {
        let orchestrator = Orchestrator {
            local: Arc::new(AlwaysOkTransport("local".into())),
            server_mux: Some(Arc::new(AlwaysErrTransport)),
            frontier: None,
        };

        let prompt = PromptRequest {
            prompt: "hello".into(),
            estimated_input_tokens: 5,
            estimated_output_tokens: 100,
            class: crate::bridge::router::PromptClass::Chat,
            privacy: crate::bridge::router::Privacy::Default,
            conversation_id: "test".into(),
        };

        let ctx = BridgeContext {
            local_tier: crate::tier::Tier::T1,
            connection_state: crate::bridge::router::ConnectionState::Online,
            latency_budget_ms: 1000,
            cost_budget_usd: 10.0,
            server_mux_endpoint: Some("http://localhost:8080".into()),
            frontier_providers_available: vec![],
            user_policy: crate::bridge::router::UserPolicy {
                prefer_local: false,
                max_cost_per_prompt_usd: 1.0,
                default_provider: None,
            },
            per_conversation_override: None,
        };

        let result = orchestrator.run(&prompt, &ctx).await;
        assert!(result.is_ok());
        let resp = result.unwrap();
        assert!(resp.source.contains("local"));
    }

    #[tokio::test]
    async fn test_offline_routes_to_local() {
        let orchestrator = Orchestrator {
            local: Arc::new(AlwaysOkTransport("local".into())),
            server_mux: Some(Arc::new(AlwaysOkTransport("servermux".into()))),
            frontier: None,
        };

        let prompt = PromptRequest {
            prompt: "hello".into(),
            estimated_input_tokens: 5,
            estimated_output_tokens: 100,
            class: crate::bridge::router::PromptClass::Chat,
            privacy: crate::bridge::router::Privacy::Default,
            conversation_id: "test".into(),
        };

        let ctx = BridgeContext {
            local_tier: crate::tier::Tier::T1,
            connection_state: crate::bridge::router::ConnectionState::Offline,
            latency_budget_ms: 1000,
            cost_budget_usd: 10.0,
            server_mux_endpoint: Some("http://localhost:8080".into()),
            frontier_providers_available: vec![],
            user_policy: crate::bridge::router::UserPolicy {
                prefer_local: false,
                max_cost_per_prompt_usd: 1.0,
                default_provider: None,
            },
            per_conversation_override: None,
        };

        let result = orchestrator.run(&prompt, &ctx).await;
        assert!(result.is_ok());
        let resp = result.unwrap();
        assert!(resp.source.contains("local"));
    }

    #[tokio::test]
    async fn test_local_failure_no_fallback() {
        let orchestrator = Orchestrator {
            local: Arc::new(AlwaysErrTransport),
            server_mux: Some(Arc::new(AlwaysOkTransport("servermux".into()))),
            frontier: None,
        };

        let prompt = PromptRequest {
            prompt: "hello".into(),
            estimated_input_tokens: 5,
            estimated_output_tokens: 100,
            class: crate::bridge::router::PromptClass::Chat,
            privacy: crate::bridge::router::Privacy::LocalOnly,
            conversation_id: "test".into(),
        };

        let ctx = BridgeContext {
            local_tier: crate::tier::Tier::T1,
            connection_state: crate::bridge::router::ConnectionState::Online,
            latency_budget_ms: 1000,
            cost_budget_usd: 10.0,
            server_mux_endpoint: Some("http://localhost:8080".into()),
            frontier_providers_available: vec![],
            user_policy: crate::bridge::router::UserPolicy {
                prefer_local: false,
                max_cost_per_prompt_usd: 1.0,
                default_provider: None,
            },
            per_conversation_override: None,
        };

        let result = orchestrator.run(&prompt, &ctx).await;
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("simulated failure"));
    }

    #[tokio::test]
    async fn test_frontier_configured_routes_to_frontier() {
        let orchestrator = Orchestrator {
            local: Arc::new(AlwaysOkTransport("local".into())),
            server_mux: Some(Arc::new(AlwaysOkTransport("servermux".into()))),
            frontier: Some(Arc::new(AlwaysOkTransport("frontier".into()))),
        };

        let prompt = PromptRequest {
            prompt: "write code".into(),
            estimated_input_tokens: 10,
            estimated_output_tokens: 500,
            class: crate::bridge::router::PromptClass::Code,
            privacy: crate::bridge::router::Privacy::AllowFrontier,
            conversation_id: "test".into(),
        };

        let ctx = BridgeContext {
            local_tier: crate::tier::Tier::T1,
            connection_state: crate::bridge::router::ConnectionState::Online,
            latency_budget_ms: 2000,
            cost_budget_usd: 0.05,
            server_mux_endpoint: Some("http://localhost:8080".into()),
            frontier_providers_available: vec!["anthropic".into()],
            user_policy: crate::bridge::router::UserPolicy {
                prefer_local: false,
                max_cost_per_prompt_usd: 0.1,
                default_provider: Some("anthropic".into()),
            },
            per_conversation_override: None,
        };

        let result = orchestrator.run(&prompt, &ctx).await;
        assert!(result.is_ok());
        let resp = result.unwrap();
        assert!(resp.source.contains("frontier"));
    }

    #[tokio::test]
    async fn test_queue_decision_returns_queued_error() {
        let orchestrator = Orchestrator {
            local: Arc::new(AlwaysOkTransport("local".into())),
            server_mux: None,
            frontier: None,
        };

        let prompt = PromptRequest {
            prompt: "hello".into(),
            estimated_input_tokens: 5,
            estimated_output_tokens: 100,
            class: crate::bridge::router::PromptClass::Chat,
            privacy: crate::bridge::router::Privacy::LocalOnly,
            conversation_id: "test".into(),
        };

        let ctx = BridgeContext {
            local_tier: crate::tier::Tier::T0,
            connection_state: crate::bridge::router::ConnectionState::Offline,
            latency_budget_ms: 50,
            cost_budget_usd: 0.0,
            server_mux_endpoint: None,
            frontier_providers_available: vec![],
            user_policy: crate::bridge::router::UserPolicy {
                prefer_local: false,
                max_cost_per_prompt_usd: 0.0,
                default_provider: None,
            },
            per_conversation_override: Some(crate::bridge::router::RouteOverride::ForceServerMux),
        };

        let result = orchestrator.run(&prompt, &ctx).await;
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.to_string().contains("queued"));
    }
}
