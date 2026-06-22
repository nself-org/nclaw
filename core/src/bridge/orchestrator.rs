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

// Tests live in `tests/bridge_orchestrator_test.rs` (uses only public API).
