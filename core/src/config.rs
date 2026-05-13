use crate::llm::RolesConfig;
use crate::tier::Tier;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use thiserror::Error;

/// Configuration errors
#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("figment error: {0}")]
    Figment(String),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("toml error: {0}")]
    Toml(String),
    #[error("config validation error: {0}")]
    Validation(String),
}

/// Server configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub url: String,       // Backend URL (e.g., http://localhost:8080)
    pub timeout_secs: u64, // Request timeout in seconds
    #[serde(default = "default_true")]
    pub insecure_skip_verify: bool, // Skip TLS verification (dev only)
}

/// LLM configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmConfig {
    #[serde(default = "default_llm_tier")]
    pub tier: String, // "free" | "pro" | "max"
    pub model_id: Option<String>,   // Override default model per tier
    pub ollama_url: Option<String>, // Local Ollama instance URL
}

/// Vault configuration (keychain/credential store access)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultConfig {
    #[serde(default = "default_vault_service")]
    pub service_name: String, // macOS Keychain service name
}

/// Sync configuration (WebSocket + polling)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    pub ws_url: String, // WebSocket URL for real-time sync
    #[serde(default = "default_polling_interval")]
    pub polling_interval_secs: u64, // Fallback polling interval
}

/// Telemetry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TelemetryConfig {
    #[serde(default)]
    pub opt_in: bool, // User telemetry opt-in
}

/// Upgrade prompt configuration
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UpgradeConfig {
    #[serde(default)]
    pub upgrade_prompt_disabled: bool, // Suppress upgrade prompts if true
    pub last_upgrade_prompt_at: Option<chrono::DateTime<chrono::Utc>>, // Last prompt time (defer 30 days)
}

/// Root configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub llm: LlmConfig,
    pub vault: VaultConfig,
    pub sync: SyncConfig,
    pub telemetry: TelemetryConfig,
    #[serde(default)]
    pub upgrade: UpgradeConfig,
    #[serde(default = "default_roles_config")]
    pub roles: RolesConfig,
}

// Defaults
fn default_true() -> bool {
    true
}
fn default_llm_tier() -> String {
    "free".to_string()
}
fn default_vault_service() -> String {
    "nClaw".to_string()
}
fn default_polling_interval() -> u64 {
    30
}
fn default_roles_config() -> RolesConfig {
    RolesConfig::default_for_tier(Tier::T2)
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig {
                url: "http://localhost:8080".to_string(),
                timeout_secs: 30,
                insecure_skip_verify: true,
            },
            llm: LlmConfig {
                tier: "free".to_string(),
                model_id: None,
                ollama_url: None,
            },
            vault: VaultConfig {
                service_name: "nClaw".to_string(),
            },
            sync: SyncConfig {
                ws_url: "ws://localhost:8080/graphql".to_string(),
                polling_interval_secs: 30,
            },
            telemetry: TelemetryConfig { opt_in: false },
            upgrade: UpgradeConfig::default(),
            roles: RolesConfig::default_for_tier(Tier::T2),
        }
    }
}

/// Get platform-appropriate config directory
fn config_dir() -> Result<PathBuf, ConfigError> {
    #[cfg(target_os = "macos")]
    {
        let mut path =
            dirs::home_dir().ok_or_else(|| ConfigError::Validation("no home dir".to_string()))?;
        path.push("Library/Application Support/nClaw");
        Ok(path)
    }
    #[cfg(target_os = "windows")]
    {
        let mut path = dirs::config_dir()
            .ok_or_else(|| ConfigError::Validation("no config dir".to_string()))?;
        path.push("nClaw");
        Ok(path)
    }
    #[cfg(target_os = "linux")]
    {
        let mut path = dirs::config_dir()
            .ok_or_else(|| ConfigError::Validation("no config dir".to_string()))?;
        path.push("nclaw");
        Ok(path)
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    {
        Err(ConfigError::Validation("unsupported platform".to_string()))
    }
}

impl Config {
    /// Load config from cascade: defaults → config.toml → env vars → override file
    pub fn load() -> Result<Config, ConfigError> {
        use figment::providers::{Env, Format, Toml};
        use figment::Figment;

        let config_path = config_dir()?.join("config.toml");
        let mut figment = Figment::new().merge(figment::value::Value::from(Config::default()));

        // Merge from config.toml if it exists
        if config_path.exists() {
            figment = figment.merge(Toml::file(&config_path));
        }

        // Merge from NCLAW_* env vars
        figment = figment.merge(Env::prefixed("NCLAW_"));

        // Merge from override file if specified
        if let Ok(override_path) = std::env::var("NCLAW_CONFIG_OVERRIDE") {
            figment = figment.merge(Toml::file(&override_path));
        }

        figment
            .extract()
            .map_err(|e| ConfigError::Figment(e.to_string()))
    }

    /// Save config to disk
    pub fn save(&self) -> Result<(), ConfigError> {
        let config_dir = config_dir()?;
        std::fs::create_dir_all(&config_dir)?;

        let config_path = config_dir.join("config.toml");
        let toml = toml::to_string_pretty(self).map_err(|e| ConfigError::Toml(e.to_string()))?;
        std::fs::write(&config_path, toml)?;
        Ok(())
    }

    /// Get the RolesConfig for a specific tier, or use the instance config if no tier specified.
    pub fn roles_for(tier: Tier) -> RolesConfig {
        RolesConfig::default_for_tier(tier)
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<(), ConfigError> {
        if self.server.url.is_empty() {
            return Err(ConfigError::Validation("server.url is empty".to_string()));
        }
        if self.sync.ws_url.is_empty() {
            return Err(ConfigError::Validation("sync.ws_url is empty".to_string()));
        }
        if !["free", "pro", "max"].contains(&self.llm.tier.as_str()) {
            return Err(ConfigError::Validation(format!(
                "invalid llm.tier: {}",
                self.llm.tier
            )));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;

    fn temp_config_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("nclaw_test_{}", uuid::Uuid::new_v4()));
        let _ = fs::create_dir_all(&dir);
        dir
    }

    #[test]
    fn test_default_config() {
        let cfg = Config::default();
        assert_eq!(cfg.server.url, "http://localhost:8080");
        assert_eq!(cfg.llm.tier, "free");
        assert!(!cfg.telemetry.opt_in);
    }

    #[test]
    fn test_config_save_load() {
        let dir = temp_config_dir();
        std::env::set_var("HOME", dir.to_string_lossy().to_string());

        let mut cfg = Config::default();
        cfg.server.url = "http://prod.server:8080".to_string();
        cfg.llm.tier = "max".to_string();
        cfg.telemetry.opt_in = true;

        cfg.save().expect("save failed");

        let loaded = Config::load().expect("load failed");
        assert_eq!(loaded.server.url, "http://prod.server:8080");
        assert_eq!(loaded.llm.tier, "max");
        assert!(loaded.telemetry.opt_in);
    }

    #[test]
    fn test_config_validate() {
        let mut cfg = Config::default();
        assert!(cfg.validate().is_ok());

        cfg.server.url.clear();
        assert!(cfg.validate().is_err());

        cfg.server.url = "http://localhost:8080".to_string();
        cfg.llm.tier = "invalid".to_string();
        assert!(cfg.validate().is_err());
    }
}
