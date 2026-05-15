// Tauri commands for Local AI Settings panel.
// Not yet available: backend wiring lands in S15.T17 acceptance gate.
// Every command returns a typed NotImplemented error until S15-T17 ships.

use chrono::Utc;
use serde::{Deserialize, Serialize};

// --- Mirror types (will match libnclaw::tier / libnclaw::registry / libnclaw::benchmark in T17) ---

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tier {
    /// Auto-detected tier (0..=4)
    pub active: u8,
    /// "auto" or "T0".."T4"
    pub r#override: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkResult {
    pub date: String,
    pub toks_per_sec: f32,
    pub model_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelEntry {
    pub model_id: String,
    pub size_mb: u64,
    pub last_used_at: Option<String>,
    pub roles: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpgradeConfig {
    pub upgrade_prompt_disabled: bool,
    pub last_upgrade_prompt_at: Option<String>,
}

// --- Commands ---

/// Returns the active hardware tier and any user override.
/// Not yet available: S15-T17 wires real nclaw-core tier detection.
#[tauri::command]
pub async fn get_tier() -> Result<Tier, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Returns the last `limit` benchmark results (most recent first).
/// Not yet available: S15-T17 wires real benchmark history from nclaw-core.
#[tauri::command]
pub async fn get_benchmark_history(_limit: usize) -> Result<Vec<BenchmarkResult>, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Lists all installed local models.
/// Not yet available: S15-T17 wires real model registry from nclaw-core.
#[tauri::command]
pub async fn list_models() -> Result<Vec<ModelEntry>, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Runs the hardware benchmark and returns the result.
/// Not yet available: S15-T17 wires real llama.cpp benchmark via nclaw-core.
#[tauri::command]
pub async fn run_benchmark() -> Result<BenchmarkResult, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Opens a file-picker dialog and imports the chosen .gguf file.
/// Returns the registered model_id.
/// Not yet available: S15-T17 wires real GGUF import via nclaw-core registry.
#[tauri::command]
pub async fn import_custom_gguf(_app: tauri::AppHandle, _path: String) -> Result<String, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Sets (or clears) the tier override. Pass `None` for Auto.
/// Not yet available: S15-T17 wires real tier override persistence.
#[tauri::command]
pub async fn set_tier_override(_tier: Option<u8>) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Enables or disables T4 (heavy) model execution.
/// Not yet available: S15-T17 wires real allow-T4 flag persistence.
#[tauri::command]
pub async fn set_allow_t4(_allow: bool) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Enables or disables the monthly auto-benchmark cron.
/// Not yet available: S15-T17 wires real cron flag persistence.
#[tauri::command]
pub async fn set_re_bench_monthly(_enabled: bool) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Deletes a local model from disk.
/// Not yet available: S15-T17 wires real model deletion via nclaw-core.
#[tauri::command]
pub async fn delete_model(_model_id: String) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Sets a model's primary inference role (chat / summarize / embed / code).
/// Not yet available: S15-T17 wires real role assignment via nclaw-core registry.
#[tauri::command]
pub async fn set_model_role(_model_id: String, _role: String) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Returns upgrade config (prompt disabled flag + deferral timestamp).
/// Not yet available: S15-T17 wires real config from nclaw-core.
#[tauri::command]
pub async fn get_upgrade_config() -> Result<UpgradeConfig, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Initiates upgrade to the specified tier (0–4).
/// For T4, the caller must show a confirmation dialog.
/// Not yet available: S15-T17 wires real upgrade flow via nclaw-core.
#[tauri::command]
pub async fn upgrade_to_tier(tier: u8) -> Result<(), String> {
    if tier > 4 {
        return Err("Invalid tier: must be 0–4".to_string());
    }
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Disables upgrade prompts until re-enabled by the user.
/// Not yet available: S15-T17 wires real flag persistence via nclaw-core.
#[tauri::command]
pub async fn set_upgrade_prompt_disabled(_disabled: bool) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}

/// Defers upgrade prompts for 30 days by updating last_upgrade_prompt_at.
/// Not yet available: S15-T17 wires real deferral timestamp via nclaw-core.
#[tauri::command]
pub async fn defer_upgrade_prompt_30_days() -> Result<(), String> {
    // Keep the Utc import used — suppress dead_code for the awaiting sprint.
    let _now = Utc::now().to_rfc3339();
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}
