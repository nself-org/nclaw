//! Request, context, and decision types for the bridge router.
//!
//! Extracted from `router/mod.rs` to keep each file under 300 lines.
//! All types are `pub` — consumed by the router logic in `mod.rs` and
//! by external callers (orchestrator, transport impls).

use serde::{Deserialize, Serialize};

use crate::tier::Tier;

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

/// Classification of the prompt's workload shape.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PromptClass {
    /// Conversational turn.
    Chat,
    /// Summarise a document or memory context.
    Summarize,
    /// Code generation or transformation.
    Code,
    /// Embedding / semantic vector generation.
    Embed,
}

/// Privacy requirement the user has configured for this prompt or conversation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Privacy {
    /// Content must never leave the device.
    LocalOnly,
    /// Default behaviour: prefer local; cloud allowed if needed.
    Default,
    /// Explicitly permit frontier cloud providers.
    AllowFrontier,
}

/// A single prompt request with enough metadata to route without I/O.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromptRequest {
    /// The prompt text.
    pub prompt: String,
    /// Estimated tokens in the prompt (used for cost estimation).
    pub estimated_input_tokens: u32,
    /// Estimated tokens expected in the response (used for cost estimation).
    pub estimated_output_tokens: u32,
    /// Workload shape.
    pub class: PromptClass,
    /// Privacy constraint.
    pub privacy: Privacy,
    /// Opaque conversation identifier.
    pub conversation_id: String,
}

// ---------------------------------------------------------------------------
// Context types
// ---------------------------------------------------------------------------

/// Network connectivity state from the perspective of the bridge.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConnectionState {
    /// Full connectivity to backend services.
    Online,
    /// Partial connectivity: local + ServerMux reachable; frontier unreliable.
    Degraded,
    /// No network. Local-only inference.
    Offline,
}

/// User-level routing policy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPolicy {
    /// Boost local route score when `true`.
    pub prefer_local: bool,
    /// Hard cap on cost per individual prompt (USD). Routes that would exceed
    /// this cap are excluded from the candidate set.
    pub max_cost_per_prompt_usd: f64,
    /// Preferred frontier provider name (e.g. `"anthropic"`). `None` = no preference.
    pub default_provider: Option<String>,
}

/// Per-conversation routing override applied before any rule evaluation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RouteOverride {
    /// Route every prompt in this conversation to local llama.cpp.
    ForceLocal,
    /// Route every prompt to the configured ServerMux endpoint.
    ForceServerMux,
    /// Route every prompt to a specific frontier provider + model.
    ForceFrontier { provider: String, model_id: String },
}

/// All context the router needs to make a decision without I/O.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeContext {
    /// Hardware tier of the local device (from `tier::classify_tier`).
    pub local_tier: Tier,
    /// Current network / backend connectivity state.
    pub connection_state: ConnectionState,
    /// Maximum acceptable end-to-end latency in milliseconds.
    pub latency_budget_ms: u32,
    /// Remaining cost budget for this session/prompt run (USD).
    pub cost_budget_usd: f64,
    /// ServerMux endpoint URL if configured; `None` = not available.
    pub server_mux_endpoint: Option<String>,
    /// Frontier provider names available right now (e.g. `["anthropic", "openai"]`).
    pub frontier_providers_available: Vec<String>,
    /// User-level routing policy.
    pub user_policy: UserPolicy,
    /// Conversation-scoped override applied before rule evaluation.
    pub per_conversation_override: Option<RouteOverride>,
}

// ---------------------------------------------------------------------------
// Decision type
// ---------------------------------------------------------------------------

/// The routing decision returned by `Router::route`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RouteDecision {
    /// Run inference locally via llama.cpp with this model.
    Local { model_id: String },
    /// Forward to a ServerMux endpoint; server selects the concrete model.
    ServerMux {
        endpoint: String,
        model_hint: String,
    },
    /// Call a frontier API directly.
    DirectFrontier { provider: String, model_id: String },
    /// No eligible route right now; enqueue for retry when connectivity returns.
    Queue { reason: String },
}
