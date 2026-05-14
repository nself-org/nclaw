//! Bridge router — core types and routing logic per Decision #11.
//!
//! Entry point: `Router::route(&PromptRequest, &BridgeContext) -> RouteDecision`.
//! Three stages: filter (eliminate ineligible routes) → score (0–100 heuristic)
//! → pick (highest score; ties broken by cost ascending, then latency ascending).

use serde::{Deserialize, Serialize};

use crate::registry;
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
#[derive(Debug, Clone, Serialize, Deserialize)]
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

// ---------------------------------------------------------------------------
// Cost estimation helpers (pseudo-rates, no I/O)
// ---------------------------------------------------------------------------

/// Estimated cost in USD for a prompt through a given route.
///
/// Rates are intentionally conservative pseudo-rates, sufficient for
/// relative comparison only — not for billing.
fn estimate_cost_usd(decision: &RouteDecision, req: &PromptRequest) -> f64 {
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
fn estimate_latency_ms(decision: &RouteDecision) -> u32 {
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

fn local_model_id(tier: Tier) -> String {
    registry::default_for_tier(tier)
        .map(|e| e.id.to_string())
        .unwrap_or_else(|| "qwen2.5-0.5b-q4km".to_string())
}

fn frontier_model_id(provider: &str) -> String {
    match provider {
        "anthropic" => "claude-sonnet-4.6".to_string(),
        "openai" => "gpt-4o-mini".to_string(),
        "google" => "gemini-1.5-flash".to_string(),
        other => format!("{}/default", other),
    }
}

fn pick_frontier_provider(ctx: &BridgeContext) -> Option<String> {
    if ctx.frontier_providers_available.is_empty() {
        return None;
    }
    // Honour user preference if that provider is available.
    if let Some(ref pref) = ctx.user_policy.default_provider {
        if ctx.frontier_providers_available.contains(pref) {
            return Some(pref.clone());
        }
    }
    // Otherwise fall back to the first available provider.
    ctx.frontier_providers_available.first().cloned()
}

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
                    // ServerMux forced but not configured — fall to local.
                    RouteDecision::Local {
                        model_id: local_model_id(ctx.local_tier),
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

                s.max(0) as u32
            }

            RouteDecision::Queue { .. } => 0,
        }
    }
}
