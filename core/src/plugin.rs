//! Plugin capability types for the nClaw plugin awareness architecture.
//!
//! Each nSelf plugin ships a `capability.json` file declaring what actions
//! nClaw can invoke on the server. At startup nClaw loads all capability
//! files and builds a dynamic tool registry from them.
//!
//! ## Example capability.json
//!
//! ```json
//! {
//!   "plugin": "nself-notify",
//!   "version": "1.0.0",
//!   "description": "Send notifications via Telegram and webhooks",
//!   "actions": [
//!     {
//!       "name": "send_notification",
//!       "description": "Send a notification to one or more channels",
//!       "endpoint": "/api/notify/send",
//!       "method": "POST",
//!       "parameters": [
//!         { "name": "channel", "type": "string", "required": true,
//!           "description": "Channel name or 'all'" },
//!         { "name": "message", "type": "string", "required": true,
//!           "description": "Notification body" }
//!       ]
//!     }
//!   ]
//! }
//! ```

use serde::{Deserialize, Serialize};

// =============================================================================
// capability.json root
// =============================================================================

/// The root of a plugin's `capability.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginCapability {
    /// Plugin identifier (e.g. `"nself-notify"`).
    pub plugin: String,
    /// Semver version of the plugin.
    pub version: String,
    /// Human-readable description shown in the tool registry.
    pub description: String,
    /// All actions this plugin exposes to nClaw.
    pub actions: Vec<PluginAction>,
    /// Optional: required permissions the user must grant before any action runs.
    #[serde(default)]
    pub required_permissions: Vec<String>,
}

// =============================================================================
// Action definition
// =============================================================================

/// A single action exposed by a plugin.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginAction {
    /// Unique action name within the plugin (e.g. `"send_notification"`).
    pub name: String,
    /// Description used as the tool description in the AI context.
    pub description: String,
    /// HTTP endpoint relative to the nSelf base URL (e.g. `"/api/notify/send"`).
    pub endpoint: String,
    /// HTTP method.
    pub method: HttpMethod,
    /// Parameters the action accepts.
    #[serde(default)]
    pub parameters: Vec<ActionParameter>,
    /// If true, nClaw must confirm with the user before calling this action.
    #[serde(default)]
    pub requires_confirmation: bool,
    /// Optional: the action returns a result the AI should read.
    #[serde(default = "default_true")]
    pub returns_result: bool,
}

fn default_true() -> bool {
    true
}

// =============================================================================
// Parameter definition
// =============================================================================

/// A single parameter for a plugin action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionParameter {
    pub name: String,
    pub description: String,
    #[serde(rename = "type")]
    pub param_type: ParamType,
    #[serde(default)]
    pub required: bool,
    /// JSON Schema enum values (for string parameters with a fixed set of values).
    #[serde(default)]
    pub enum_values: Vec<String>,
    /// Default value (JSON).
    pub default: Option<serde_json::Value>,
}

/// JSON-schema-compatible parameter types.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ParamType {
    String,
    Number,
    Integer,
    Boolean,
    Array,
    Object,
}

/// HTTP method for an action endpoint.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Delete,
}

// =============================================================================
// Runtime registry entry
// =============================================================================

/// A fully-resolved action ready for use in the AI tool registry.
/// Built from `PluginCapability` at startup.
#[derive(Debug, Clone)]
pub struct RegisteredAction {
    /// Full tool name used in AI context: `<plugin>__<action>` (e.g. `"nself_notify__send_notification"`).
    pub tool_name: String,
    pub plugin: String,
    pub action: PluginAction,
    /// Absolute URL for the action endpoint.
    pub url: String,
}

impl RegisteredAction {
    /// Build a `RegisteredAction` from a capability + base URL.
    pub fn from_capability(
        cap: &PluginCapability,
        action: &PluginAction,
        base_url: &str,
    ) -> Self {
        let tool_name = format!(
            "{}__{}",
            cap.plugin.replace('-', "_"),
            action.name
        );
        let url = format!("{}{}", base_url.trim_end_matches('/'), action.endpoint);
        Self {
            tool_name,
            plugin: cap.plugin.clone(),
            action: action.clone(),
            url,
        }
    }
}

// =============================================================================
// Registry
// =============================================================================

/// The in-memory tool registry built from all loaded capabilities.
#[derive(Debug, Default)]
pub struct ToolRegistry {
    actions: Vec<RegisteredAction>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register all actions from a capability.
    pub fn register(&mut self, cap: &PluginCapability, base_url: &str) {
        for action in &cap.actions {
            self.actions.push(RegisteredAction::from_capability(cap, action, base_url));
        }
    }

    /// Look up an action by its tool name.
    pub fn get(&self, tool_name: &str) -> Option<&RegisteredAction> {
        self.actions.iter().find(|a| a.tool_name == tool_name)
    }

    /// All registered actions.
    pub fn all(&self) -> &[RegisteredAction] {
        &self.actions
    }

    /// Total number of registered actions.
    pub fn len(&self) -> usize {
        self.actions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.actions.is_empty()
    }
}
