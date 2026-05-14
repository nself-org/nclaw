//! Bridge rule types — built-in rules and user/per-conversation override types.
//!
//! The router applies these rules in order (per Decision #11):
//!   1. Per-conversation `RouteOverride` (hard override, always wins)
//!   2. Built-in filter rules (eliminate ineligible routes)
//!   3. Built-in score rules (heuristic ranking)
//!
//! Rule types are exposed here for introspection and future user-configurable
//! rule lists. The router itself lives in `bridge::router`.

use serde::{Deserialize, Serialize};

use crate::bridge::router::{ConnectionState, Privacy, PromptClass, RouteOverride};

// ---------------------------------------------------------------------------
// Built-in filter rule descriptors
// ---------------------------------------------------------------------------

/// A named filter rule that can eliminate a route from the candidate set.
///
/// Rules are evaluated as a conjunction: a route is eligible only when
/// NONE of the active `FilterRule`s block it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum FilterRule {
    /// Block cloud routes when privacy is `LocalOnly`.
    PrivacyLocalOnlyBlocksCloud,
    /// Block all non-local routes when the connection is `Offline`.
    OfflineBlocksCloud,
    /// Block `DirectFrontier` when the connection is `Degraded`.
    DegradedBlocksFrontier,
    /// Block `DirectFrontier` when no frontier provider is configured.
    NoProvidersBlocksFrontier,
    /// Block `ServerMux` when no endpoint is configured.
    NoEndpointBlocksServerMux,
    /// Block any route whose estimated cost exceeds the user's per-prompt budget.
    CostBudgetExceeded,
}

impl FilterRule {
    /// Human-readable description of the rule.
    pub fn description(&self) -> &'static str {
        match self {
            Self::PrivacyLocalOnlyBlocksCloud => {
                "LocalOnly privacy: cloud routes (ServerMux, DirectFrontier) are ineligible"
            }
            Self::OfflineBlocksCloud => "Offline connection: only local inference is eligible",
            Self::DegradedBlocksFrontier => {
                "Degraded connection: DirectFrontier is ineligible; ServerMux allowed"
            }
            Self::NoProvidersBlocksFrontier => {
                "No frontier providers configured: DirectFrontier is ineligible"
            }
            Self::NoEndpointBlocksServerMux => {
                "No ServerMux endpoint configured: ServerMux is ineligible"
            }
            Self::CostBudgetExceeded => "Estimated prompt cost exceeds max_cost_per_prompt_usd",
        }
    }

    /// Returns all filter rules that are active for the given conditions.
    pub fn active_for(
        privacy: Privacy,
        connection: ConnectionState,
        has_endpoint: bool,
        has_providers: bool,
    ) -> Vec<FilterRule> {
        let mut active = Vec::new();

        if privacy == Privacy::LocalOnly {
            active.push(FilterRule::PrivacyLocalOnlyBlocksCloud);
        }
        if connection == ConnectionState::Offline {
            active.push(FilterRule::OfflineBlocksCloud);
        }
        if connection == ConnectionState::Degraded {
            active.push(FilterRule::DegradedBlocksFrontier);
        }
        if !has_endpoint {
            active.push(FilterRule::NoEndpointBlocksServerMux);
        }
        if !has_providers {
            active.push(FilterRule::NoProvidersBlocksFrontier);
        }

        active
    }
}

// ---------------------------------------------------------------------------
// Built-in score rule descriptors
// ---------------------------------------------------------------------------

/// A named score adjustment applied during the scoring stage.
///
/// Score adjustments are additive. The total for any route is clamped to [0, 100].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ScoreRule {
    /// +20 to Local when `user_policy.prefer_local` is true.
    LocalPreferred,
    /// +10 to Local for `Embed` workloads (fast + cheap locally).
    LocalEmbedBoost,
    /// -30 to Local for `Code` workloads on T0/T1 tiers (insufficient capability).
    LocalCodePenaltyLowTier,
    /// +10 to ServerMux when connection is `Online`.
    ServerMuxOnlineBoost,
    /// -10 to ServerMux when cost is approaching the budget threshold (>70%).
    ServerMuxCostWarning,
    /// +20 to DirectFrontier for `Code` workloads (frontier excels at code).
    FrontierCodeBoost,
    /// -20 to DirectFrontier when privacy is `Default` (slight cloud penalty).
    FrontierDefaultPrivacyPenalty,
}

impl ScoreRule {
    /// Human-readable description.
    pub fn description(&self) -> &'static str {
        match self {
            Self::LocalPreferred => "+20 to Local: user prefers local inference",
            Self::LocalEmbedBoost => "+10 to Local: Embed workloads are cheap locally",
            Self::LocalCodePenaltyLowTier => {
                "-30 to Local: T0/T1 tier insufficient for Code workloads"
            }
            Self::ServerMuxOnlineBoost => "+10 to ServerMux: full connectivity available",
            Self::ServerMuxCostWarning => {
                "-10 to ServerMux: prompt cost approaching budget threshold"
            }
            Self::FrontierCodeBoost => "+20 to DirectFrontier: frontier excels at Code",
            Self::FrontierDefaultPrivacyPenalty => {
                "-20 to DirectFrontier: slight penalty for Default privacy sending to cloud"
            }
        }
    }

    /// Score delta (positive or negative).
    pub fn delta(&self) -> i32 {
        match self {
            Self::LocalPreferred => 20,
            Self::LocalEmbedBoost => 10,
            Self::LocalCodePenaltyLowTier => -30,
            Self::ServerMuxOnlineBoost => 10,
            Self::ServerMuxCostWarning => -10,
            Self::FrontierCodeBoost => 20,
            Self::FrontierDefaultPrivacyPenalty => -20,
        }
    }

    /// Which class of workloads this rule applies to. `None` = all classes.
    pub fn applies_to_class(&self) -> Option<PromptClass> {
        match self {
            Self::LocalEmbedBoost => Some(PromptClass::Embed),
            Self::LocalCodePenaltyLowTier => Some(PromptClass::Code),
            Self::FrontierCodeBoost => Some(PromptClass::Code),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// User-configurable rule list
// ---------------------------------------------------------------------------

/// A user-supplied routing policy expressed as an ordered list of overrides
/// and score adjustments. Applied after built-in rules but before tie-breaking.
///
/// Currently descriptive only (the router uses `RouteOverride` directly from
/// `BridgeContext`). This type is reserved for a future rule-engine extension
/// where users can define custom routing logic.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserRuleSet {
    /// Per-conversation override (equivalent to `BridgeContext::per_conversation_override`).
    pub conversation_override: Option<RouteOverride>,
    /// Additional score boosts (provider name → extra score delta).
    pub provider_boosts: Vec<ProviderBoost>,
}

/// A user-defined score boost for a specific frontier provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderBoost {
    /// Provider name (e.g. `"anthropic"`).
    pub provider: String,
    /// Score delta to add when this provider is selected as a `DirectFrontier` candidate.
    pub delta: i32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filter_rule_descriptions_non_empty() {
        let rules = [
            FilterRule::PrivacyLocalOnlyBlocksCloud,
            FilterRule::OfflineBlocksCloud,
            FilterRule::DegradedBlocksFrontier,
            FilterRule::NoProvidersBlocksFrontier,
            FilterRule::NoEndpointBlocksServerMux,
            FilterRule::CostBudgetExceeded,
        ];
        for r in &rules {
            assert!(
                !r.description().is_empty(),
                "{:?} description must not be empty",
                r
            );
        }
    }

    #[test]
    fn score_rule_deltas_non_zero() {
        let rules = [
            ScoreRule::LocalPreferred,
            ScoreRule::LocalEmbedBoost,
            ScoreRule::LocalCodePenaltyLowTier,
            ScoreRule::ServerMuxOnlineBoost,
            ScoreRule::ServerMuxCostWarning,
            ScoreRule::FrontierCodeBoost,
            ScoreRule::FrontierDefaultPrivacyPenalty,
        ];
        for r in &rules {
            assert_ne!(r.delta(), 0, "{:?} delta must be non-zero", r);
        }
    }

    #[test]
    fn active_filter_rules_offline_and_local_only() {
        let active =
            FilterRule::active_for(Privacy::LocalOnly, ConnectionState::Offline, false, false);
        // PrivacyLocalOnlyBlocksCloud + OfflineBlocksCloud + NoEndpoint + NoProviders
        assert!(active.contains(&FilterRule::PrivacyLocalOnlyBlocksCloud));
        assert!(active.contains(&FilterRule::OfflineBlocksCloud));
        assert!(active.contains(&FilterRule::NoEndpointBlocksServerMux));
        assert!(active.contains(&FilterRule::NoProvidersBlocksFrontier));
        // DegradedBlocksFrontier should NOT be active when Offline
        assert!(!active.contains(&FilterRule::DegradedBlocksFrontier));
    }

    #[test]
    fn active_filter_rules_degraded() {
        let active =
            FilterRule::active_for(Privacy::Default, ConnectionState::Degraded, true, true);
        assert!(active.contains(&FilterRule::DegradedBlocksFrontier));
        assert!(!active.contains(&FilterRule::OfflineBlocksCloud));
        assert!(!active.contains(&FilterRule::PrivacyLocalOnlyBlocksCloud));
    }

    #[test]
    fn active_filter_rules_online_all_available() {
        let active =
            FilterRule::active_for(Privacy::AllowFrontier, ConnectionState::Online, true, true);
        assert!(
            active.is_empty(),
            "no filter rules should fire when fully available"
        );
    }

    #[test]
    fn score_rule_applies_to_class() {
        assert_eq!(
            ScoreRule::LocalEmbedBoost.applies_to_class(),
            Some(PromptClass::Embed)
        );
        assert_eq!(
            ScoreRule::FrontierCodeBoost.applies_to_class(),
            Some(PromptClass::Code)
        );
        assert_eq!(ScoreRule::LocalPreferred.applies_to_class(), None);
    }
}
