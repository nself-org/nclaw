//! Routing helpers — cost/latency estimation and model hint selection.
//!
//! Extracted from `router/mod.rs` to keep each file under 300 lines.
//! All functions are `pub(super)` — consumed only by the router logic.

use super::types::{BridgeContext, PromptRequest, RouteDecision};
use crate::registry;
use crate::tier::Tier;

// ---------------------------------------------------------------------------
// Cost estimation helpers (pseudo-rates, no I/O)
// ---------------------------------------------------------------------------

/// Estimated cost in USD for a prompt through a given route.
///
/// Rates are intentionally conservative pseudo-rates, sufficient for
/// relative comparison only — not for billing.
pub(super) fn estimate_cost_usd(decision: &RouteDecision, req: &PromptRequest) -> f64 {
    let total_tokens = (req.estimated_input_tokens + req.estimated_output_tokens) as f64;
    match decision {
        RouteDecision::Local { .. } => 0.0,
        RouteDecision::ServerMux { .. } => total_tokens / 1000.0 * 0.001,
        RouteDecision::DirectFrontier { .. } => total_tokens / 1000.0 * 0.015,
        RouteDecision::Queue { .. } => 0.0,
    }
}

/// Estimated latency in milliseconds for a given route.
///
/// Pure heuristics for relative ordering; the router does not make real
/// network measurements.
pub(super) fn estimate_latency_ms(decision: &RouteDecision) -> u32 {
    match decision {
        RouteDecision::Local { .. } => 200,
        RouteDecision::ServerMux { .. } => 600,
        RouteDecision::DirectFrontier { .. } => 900,
        RouteDecision::Queue { .. } => u32::MAX,
    }
}

// ---------------------------------------------------------------------------
// Default model hint helpers
// ---------------------------------------------------------------------------

/// Returns the default local model id for the given device tier.
pub(super) fn local_model_id(tier: Tier) -> String {
    registry::default_for_tier(tier)
        .map(|e| e.id.to_string())
        .unwrap_or_else(|| "qwen2.5-0.5b-q4km".to_string())
}

/// Returns the canonical frontier model id for the given provider name.
pub(super) fn frontier_model_id(provider: &str) -> String {
    match provider {
        "anthropic" => "claude-sonnet-4.6".to_string(),
        "openai" => "gpt-4o-mini".to_string(),
        "google" => "gemini-1.5-flash".to_string(),
        other => format!("{}/default", other),
    }
}

/// Selects the preferred frontier provider from those available in `ctx`.
///
/// Respects `UserPolicy::default_provider` if the preferred provider is
/// currently available; otherwise returns the first available provider.
pub(super) fn pick_frontier_provider(ctx: &BridgeContext) -> Option<String> {
    if ctx.frontier_providers_available.is_empty() {
        return None;
    }
    if let Some(ref pref) = ctx.user_policy.default_provider {
        if ctx.frontier_providers_available.contains(pref) {
            return Some(pref.clone());
        }
    }
    ctx.frontier_providers_available.first().cloned()
}
