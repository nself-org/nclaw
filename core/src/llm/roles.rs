//! Multi-model role-specific configuration.
//!
//! Per Decision #9:
//! - T0/T1 → all four roles (Chat, Summarize, Embed, Code) use the tier's default model
//! - T2+   → Chat, Summarize, Code = tier default; Embed = BGE-small (specialized for semantic search)
//!
//! Developer mode allows users to enable the Code role; disabled by default in production.

use crate::llm::sampling::Role;
use crate::tier::Tier;
use serde::{Deserialize, Serialize};

/// Role-to-model mapping for a single nClaw instance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelRoles {
    /// Model ID for Chat role (conversation, general instruction)
    pub chat: String,
    /// Model ID for Summarize role (document condensation, abstractive)
    pub summarize: String,
    /// Model ID for Embed role (vector embeddings, semantic search)
    pub embed: String,
    /// Model ID for Code role (code generation, IDE assistance)
    pub code: String,
}

impl ModelRoles {
    /// Compute the default role-to-model mapping for a given tier.
    ///
    /// Per Decision #9:
    /// - T0: all four roles = qwen2.5-0.5b-q4km
    /// - T1: all four roles = llama3.2-1b-q4km
    /// - T2+: chat/summarize/code = tier default; embed = bge-small-en-v1.5
    pub fn defaults_for_tier(tier: Tier) -> Self {
        let tier_default = crate::registry::default_for_tier(tier)
            .map(|e| e.id.to_string())
            .unwrap_or_else(|| "llama3.2-3b-q4km".to_string());

        let embed_id = match tier {
            Tier::T0 | Tier::T1 => tier_default.clone(),
            _ => "bge-small-en-v1.5".to_string(),
        };

        Self {
            chat: tier_default.clone(),
            summarize: tier_default.clone(),
            code: tier_default,
            embed: embed_id,
        }
    }

    /// Get the model ID for a specific role.
    pub fn get(&self, role: Role) -> &str {
        match role {
            Role::Chat => &self.chat,
            Role::Summarize => &self.summarize,
            Role::Embed => &self.embed,
            Role::Code => &self.code,
        }
    }

    /// Set the model ID for a specific role.
    pub fn set(&mut self, role: Role, model_id: impl Into<String>) {
        let id = model_id.into();
        match role {
            Role::Chat => self.chat = id,
            Role::Summarize => self.summarize = id,
            Role::Embed => self.embed = id,
            Role::Code => self.code = id,
        }
    }
}

/// Full roles configuration including developer mode control.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RolesConfig {
    /// The role-to-model mapping
    pub roles: ModelRoles,
    /// When false, the Code role is disabled (even if configured)
    pub developer_mode: bool,
}

impl RolesConfig {
    /// Create a new RolesConfig with defaults for the given tier.
    pub fn default_for_tier(tier: Tier) -> Self {
        Self {
            roles: ModelRoles::defaults_for_tier(tier),
            developer_mode: false,
        }
    }

    /// Returns the list of active (Role, model_id) pairs.
    ///
    /// When developer_mode is false, the Code role is excluded.
    pub fn active_models(&self) -> Vec<(Role, &str)> {
        let mut out = vec![
            (Role::Chat, self.roles.chat.as_str()),
            (Role::Summarize, self.roles.summarize.as_str()),
            (Role::Embed, self.roles.embed.as_str()),
        ];
        if self.developer_mode {
            out.push((Role::Code, self.roles.code.as_str()));
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_for_tier_t0_all_same() {
        let roles = ModelRoles::defaults_for_tier(Tier::T0);
        assert_eq!(roles.chat, "qwen2.5-0.5b-q4km");
        assert_eq!(roles.summarize, "qwen2.5-0.5b-q4km");
        assert_eq!(roles.embed, "qwen2.5-0.5b-q4km");
        assert_eq!(roles.code, "qwen2.5-0.5b-q4km");
    }

    #[test]
    fn defaults_for_tier_t1_all_same() {
        let roles = ModelRoles::defaults_for_tier(Tier::T1);
        assert_eq!(roles.chat, "llama3.2-1b-q4km");
        assert_eq!(roles.summarize, "llama3.2-1b-q4km");
        assert_eq!(roles.embed, "llama3.2-1b-q4km");
        assert_eq!(roles.code, "llama3.2-1b-q4km");
    }

    #[test]
    fn defaults_for_tier_t2_embed_specialized() {
        let roles = ModelRoles::defaults_for_tier(Tier::T2);
        assert_eq!(roles.chat, "llama3.2-3b-q4km");
        assert_eq!(roles.summarize, "llama3.2-3b-q4km");
        assert_eq!(roles.code, "llama3.2-3b-q4km");
        assert_eq!(roles.embed, "bge-small-en-v1.5");
    }

    #[test]
    fn defaults_for_tier_t3_embed_specialized() {
        let roles = ModelRoles::defaults_for_tier(Tier::T3);
        assert_eq!(roles.chat, "llama3.1-8b-q4km");
        assert_eq!(roles.summarize, "llama3.1-8b-q4km");
        assert_eq!(roles.code, "llama3.1-8b-q4km");
        assert_eq!(roles.embed, "bge-small-en-v1.5");
    }

    #[test]
    fn defaults_for_tier_t4_embed_specialized() {
        let roles = ModelRoles::defaults_for_tier(Tier::T4);
        assert_eq!(roles.chat, "qwen2.5-14b-q4km");
        assert_eq!(roles.summarize, "qwen2.5-14b-q4km");
        assert_eq!(roles.code, "qwen2.5-14b-q4km");
        assert_eq!(roles.embed, "bge-small-en-v1.5");
    }

    #[test]
    fn active_models_dev_mode_false() {
        let config = RolesConfig {
            roles: ModelRoles::defaults_for_tier(Tier::T2),
            developer_mode: false,
        };
        let active = config.active_models();
        assert_eq!(active.len(), 3);
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Chat)));
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Summarize)));
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Embed)));
        assert!(!active.iter().any(|(r, _)| matches!(r, Role::Code)));
    }

    #[test]
    fn active_models_dev_mode_true() {
        let config = RolesConfig {
            roles: ModelRoles::defaults_for_tier(Tier::T2),
            developer_mode: true,
        };
        let active = config.active_models();
        assert_eq!(active.len(), 4);
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Chat)));
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Summarize)));
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Embed)));
        assert!(active.iter().any(|(r, _)| matches!(r, Role::Code)));
    }

    #[test]
    fn model_roles_get_and_set() {
        let mut roles = ModelRoles::defaults_for_tier(Tier::T2);
        assert_eq!(roles.get(Role::Chat), "llama3.2-3b-q4km");

        roles.set(Role::Chat, "phi3.5-mini-q4km");
        assert_eq!(roles.get(Role::Chat), "phi3.5-mini-q4km");
    }
}
