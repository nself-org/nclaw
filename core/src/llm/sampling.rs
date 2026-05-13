use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SamplingParams {
    pub temperature: f32,    // 0.0–2.0
    pub top_p: f32,          // 0.0–1.0
    pub top_k: u32,          // 0 = disabled
    pub repeat_penalty: f32, // 1.0 = none
    pub max_tokens: u32,
    pub stop_sequences: Vec<String>,
    pub mirostat: Option<MirostatConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MirostatConfig {
    pub mode: u8, // 0 = off, 1 = v1, 2 = v2
    pub tau: f32, // target perplexity
    pub eta: f32, // learning rate
}

impl Default for SamplingParams {
    fn default() -> Self {
        Self {
            temperature: 0.7,
            top_p: 0.95,
            top_k: 40,
            repeat_penalty: 1.1,
            max_tokens: 1024,
            stop_sequences: vec![],
            mirostat: None,
        }
    }
}

impl SamplingParams {
    pub fn validate(&self) -> Result<(), String> {
        if !(0.0..=2.0).contains(&self.temperature) {
            return Err(format!(
                "temperature must be in [0.0, 2.0], got {}",
                self.temperature
            ));
        }
        if !(0.0..=1.0).contains(&self.top_p) {
            return Err(format!("top_p must be in [0.0, 1.0], got {}", self.top_p));
        }
        if self.top_k > 200 {
            return Err(format!("top_k must be <= 200, got {}", self.top_k));
        }
        if !(0.5..=2.0).contains(&self.repeat_penalty) {
            return Err(format!(
                "repeat_penalty must be in [0.5, 2.0], got {}",
                self.repeat_penalty
            ));
        }
        if let Some(m) = &self.mirostat {
            if !matches!(m.mode, 0 | 1 | 2) {
                return Err(format!("mirostat.mode must be 0, 1, or 2, got {}", m.mode));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Role {
    Chat,
    Summarize,
    Embed,
    Code,
}

pub fn defaults_for(role: Role) -> SamplingParams {
    match role {
        Role::Chat => SamplingParams {
            temperature: 0.7,
            top_p: 0.95,
            top_k: 40,
            repeat_penalty: 1.1,
            max_tokens: 1024,
            stop_sequences: vec![],
            mirostat: None,
        },
        Role::Summarize => SamplingParams {
            temperature: 0.3,
            top_p: 0.9,
            top_k: 40,
            repeat_penalty: 1.05,
            max_tokens: 512,
            stop_sequences: vec![],
            mirostat: None,
        },
        Role::Code => SamplingParams {
            temperature: 0.2,
            top_p: 0.95,
            top_k: 30,
            repeat_penalty: 1.0,
            max_tokens: 2048,
            stop_sequences: vec![],
            mirostat: None,
        },
        Role::Embed => SamplingParams {
            temperature: 0.0,
            top_p: 1.0,
            top_k: 0,
            repeat_penalty: 1.0,
            max_tokens: 0,
            stop_sequences: vec![],
            mirostat: None,
        },
    }
}

pub fn all_role_defaults() -> HashMap<Role, SamplingParams> {
    [Role::Chat, Role::Summarize, Role::Code, Role::Embed]
        .into_iter()
        .map(|r| (r, defaults_for(r)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_defaults_for_chat() {
        let params = defaults_for(Role::Chat);
        assert_eq!(params.temperature, 0.7);
        assert_eq!(params.top_p, 0.95);
        assert_eq!(params.top_k, 40);
        assert_eq!(params.repeat_penalty, 1.1);
        assert_eq!(params.max_tokens, 1024);
    }

    #[test]
    fn test_defaults_for_summarize() {
        let params = defaults_for(Role::Summarize);
        assert_eq!(params.temperature, 0.3);
        assert_eq!(params.top_p, 0.9);
        assert_eq!(params.max_tokens, 512);
    }

    #[test]
    fn test_defaults_for_code() {
        let params = defaults_for(Role::Code);
        assert_eq!(params.temperature, 0.2);
        assert_eq!(params.top_k, 30);
        assert_eq!(params.max_tokens, 2048);
    }

    #[test]
    fn test_defaults_for_embed() {
        let params = defaults_for(Role::Embed);
        assert_eq!(params.temperature, 0.0);
        assert_eq!(params.top_p, 1.0);
        assert_eq!(params.top_k, 0);
        assert_eq!(params.max_tokens, 0);
    }

    #[test]
    fn test_validate_rejects_temperature_above_2() {
        let mut params = SamplingParams::default();
        params.temperature = 3.0;
        assert!(params.validate().is_err());
    }

    #[test]
    fn test_validate_rejects_top_p_above_1() {
        let mut params = SamplingParams::default();
        params.top_p = 1.5;
        assert!(params.validate().is_err());
    }

    #[test]
    fn test_validate_rejects_top_k_above_200() {
        let mut params = SamplingParams::default();
        params.top_k = 500;
        assert!(params.validate().is_err());
    }

    #[test]
    fn test_validate_rejects_repeat_penalty_below_0_5() {
        let mut params = SamplingParams::default();
        params.repeat_penalty = 0.1;
        assert!(params.validate().is_err());
    }

    #[test]
    fn test_validate_rejects_mirostat_invalid_mode() {
        let mut params = SamplingParams::default();
        params.mirostat = Some(MirostatConfig {
            mode: 3,
            tau: 5.0,
            eta: 0.1,
        });
        assert!(params.validate().is_err());
    }

    #[test]
    fn test_validate_accepts_well_formed_params() {
        let params = SamplingParams {
            temperature: 0.7,
            top_p: 0.95,
            top_k: 40,
            repeat_penalty: 1.1,
            max_tokens: 1024,
            stop_sequences: vec![],
            mirostat: Some(MirostatConfig {
                mode: 2,
                tau: 5.0,
                eta: 0.1,
            }),
        };
        assert!(params.validate().is_ok());
    }

    #[test]
    fn test_mirostat_roundtrip_serialization() {
        let original = SamplingParams {
            temperature: 0.8,
            top_p: 0.9,
            top_k: 50,
            repeat_penalty: 1.2,
            max_tokens: 2048,
            stop_sequences: vec!["<stop>".to_string()],
            mirostat: Some(MirostatConfig {
                mode: 1,
                tau: 4.5,
                eta: 0.15,
            }),
        };
        let json = serde_json::to_string(&original).unwrap();
        let deserialized: SamplingParams = serde_json::from_str(&json).unwrap();
        assert_eq!(original.temperature, deserialized.temperature);
        assert_eq!(
            original.mirostat.unwrap().mode,
            deserialized.mirostat.unwrap().mode
        );
    }

    #[test]
    fn test_all_role_defaults_contains_all_roles() {
        let defaults = all_role_defaults();
        assert_eq!(defaults.len(), 4);
        assert!(defaults.contains_key(&Role::Chat));
        assert!(defaults.contains_key(&Role::Summarize));
        assert!(defaults.contains_key(&Role::Code));
        assert!(defaults.contains_key(&Role::Embed));
    }
}
