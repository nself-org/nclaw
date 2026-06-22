//! Bridge router — core routing logic per Decision #11.
//!
//! Entry point: `Router::route(&PromptRequest, &BridgeContext) -> RouteDecision`.
//! Three stages: filter (eliminate ineligible routes) → score (0–100 heuristic)
//! → pick (highest score; ties broken by cost ascending, then latency ascending).
//!
//! # Submodules
//!
//! - `types` — request, context, and decision types (extracted for size compliance).
//! - `helpers` — cost/latency estimation and model hint selection (extracted for size compliance).

mod helpers;
mod types;

// Re-export all types for callers who use `crate::bridge::router::*`.
pub use types::{
    BridgeContext, ConnectionState, Privacy, PromptClass, PromptRequest, RouteDecision,
    RouteOverride, UserPolicy,
};

use crate::tier::Tier;
use helpers::{estimate_cost_usd, estimate_latency_ms, frontier_model_id, local_model_id, pick_frontier_provider};

// ---------------------------------------------------------------------------
// Router — filter → score → pick
// ---------------------------------------------------------------------------

/// Stateless router. All methods are pure functions.
pub struct Router;

impl Router {
    /// Compute a `RouteDecision` for `req` given the current `ctx`.
    ///
    /// Pipeline:
    /// 1. Per-conversation override wins immediately.
    /// 2. Build candidate list (filter ineligible routes).
    /// 3. Score each candidate (0–100 heuristic).
    /// 4. Pick highest score; ties broken by cost ascending then latency ascending.
    pub fn route(req: &PromptRequest, ctx: &BridgeContext) -> RouteDecision {
        // Stage 1: hard override.
        if let Some(ref ovr) = ctx.per_conversation_override {
            return Self::apply_override(ovr, req, ctx);
        }

        // Stage 2: filter.
        let candidates = Self::eligible_routes(req, ctx);
        if candidates.is_empty() {
            return RouteDecision::Queue {
                reason: "no eligible route".into(),
            };
        }

        // Stage 3: score.
        let mut scored: Vec<(RouteDecision, u32)> = candidates
            .into_iter()
            .map(|c| {
                let s = Self::score(&c, req, ctx);
                (c, s)
            })
            .collect();

        // Stage 4: pick — highest score, ties by cost asc then latency asc.
        scored.sort_by(|(a, sa), (b, sb)| {
            sb.cmp(sa) // descending score
                .then_with(|| {
                    estimate_cost_usd(a, req)
                        .partial_cmp(&estimate_cost_usd(b, req))
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
                .then_with(|| estimate_latency_ms(a).cmp(&estimate_latency_ms(b)))
        });

        scored
            .into_iter()
            .next()
            .map(|(d, _)| d)
            .unwrap_or(RouteDecision::Queue {
                reason: "scoring failed".into(),
            })
    }

    // -----------------------------------------------------------------------
    // Internal: apply override
    // -----------------------------------------------------------------------

    fn apply_override(
        ovr: &RouteOverride,
        _req: &PromptRequest,
        ctx: &BridgeContext,
    ) -> RouteDecision {
        match ovr {
            RouteOverride::ForceLocal => RouteDecision::Local {
                model_id: local_model_id(ctx.local_tier),
            },
            RouteOverride::ForceServerMux => {
                if let Some(ref ep) = ctx.server_mux_endpoint {
                    RouteDecision::ServerMux {
                        endpoint: ep.clone(),
                        model_hint: "auto".into(),
                    }
                } else {
                    // ServerMux forced but not configured — honor user's explicit
                    // override by returning Queue rather than silently falling back
                    // to Local. This preserves the override's semantic intent.
                    RouteDecision::Queue {
                        reason: "ServerMux forced but endpoint not configured".into(),
                    }
                }
            }
            RouteOverride::ForceFrontier { provider, model_id } => RouteDecision::DirectFrontier {
                provider: provider.clone(),
                model_id: model_id.clone(),
            },
        }
    }

    // -----------------------------------------------------------------------
    // Internal: filter — build the eligible candidate set
    // -----------------------------------------------------------------------

    fn eligible_routes(req: &PromptRequest, ctx: &BridgeContext) -> Vec<RouteDecision> {
        let mut candidates = Vec::new();

        // --- Local route ---
        // Always in principle available; excluded only when the local tier is
        // fundamentally insufficient for the workload AND a better route exists
        // (handled by score rather than filter — we always include Local here so
        // that the Queue fallback only fires when *all* routes are ineligible).
        candidates.push(RouteDecision::Local {
            model_id: local_model_id(ctx.local_tier),
        });

        // --- ServerMux route ---
        // Requires: endpoint configured + not Offline + not LocalOnly.
        if ctx.server_mux_endpoint.is_some()
            && ctx.connection_state != ConnectionState::Offline
            && req.privacy != Privacy::LocalOnly
        {
            candidates.push(RouteDecision::ServerMux {
                // SAFETY: guarded by `ctx.server_mux_endpoint.is_some()` two
                // lines above; the value cannot be None at this point.
                endpoint: ctx.server_mux_endpoint.clone().unwrap(),
                model_hint: "auto".into(),
            });
        }

        // --- DirectFrontier route ---
        // Requires: Online connection + providers available + privacy != LocalOnly
        //           + Degraded is blocked (Degraded allows ServerMux but not Frontier).
        if ctx.connection_state == ConnectionState::Online
            && !ctx.frontier_providers_available.is_empty()
            && req.privacy != Privacy::LocalOnly
        {
            if let Some(provider) = pick_frontier_provider(ctx) {
                let model_id = frontier_model_id(&provider);
                let candidate = RouteDecision::DirectFrontier {
                    provider: provider.clone(),
                    model_id,
                };
                // Exclude if cost would exceed budget.
                if estimate_cost_usd(&candidate, req) <= ctx.user_policy.max_cost_per_prompt_usd {
                    candidates.push(candidate);
                }
            }
        }

        candidates
    }

    // -----------------------------------------------------------------------
    // Internal: score — 0–100 heuristic
    // -----------------------------------------------------------------------

    fn score(decision: &RouteDecision, req: &PromptRequest, ctx: &BridgeContext) -> u32 {
        match decision {
            RouteDecision::Local { .. } => {
                let mut s: i32 = 50;

                // User prefers local.
                if ctx.user_policy.prefer_local {
                    s += 20;
                }

                // Embed is cheap and fast locally.
                if req.class == PromptClass::Embed {
                    s += 10;
                }

                // T0/T1 local tier is insufficient for Code workloads.
                if (ctx.local_tier == Tier::T0 || ctx.local_tier == Tier::T1)
                    && req.class == PromptClass::Code
                {
                    s -= 30;
                }

                s.max(0) as u32
            }

            RouteDecision::ServerMux { .. } => {
                let mut s: i32 = 60;

                if ctx.connection_state == ConnectionState::Online {
                    s += 10;
                }

                // Penalise if approaching cost budget.
                let cost = estimate_cost_usd(decision, req);
                if ctx.cost_budget_usd > 0.0 && cost / ctx.cost_budget_usd > 0.7 {
                    s -= 10;
                }

                s.max(0) as u32
            }

            RouteDecision::DirectFrontier { .. } => {
                let mut s: i32 = 40;

                // Frontier excels at code.
                if req.class == PromptClass::Code {
                    s += 20;
                }

                // Slight cloud penalty for Default privacy.
                if req.privacy == Privacy::Default {
                    s -= 20;
                }

                // User explicitly opted into frontier — boost so frontier wins
                // over ServerMux when both are eligible.
                if req.privacy == Privacy::AllowFrontier {
                    s += 20;
                }

                s.max(0) as u32
            }

            RouteDecision::Queue { .. } => 0,
        }
    }
}

// Tests live in `tests/bridge_router_test.rs` (uses only public API).
