// Tauri commands for Local AI Settings panel.
// stub: returns canned data; backend wiring lands in S15.T17 acceptance gate

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
#[tauri::command]
pub async fn get_tier() -> Result<Tier, String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    Ok(Tier {
        active: 2,
        r#override: "auto".to_string(),
    })
}

/// Returns the last `limit` benchmark results (most recent first).
#[tauri::command]
pub async fn get_benchmark_history(limit: usize) -> Result<Vec<BenchmarkResult>, String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let results = vec![
        BenchmarkResult {
            date: "2026-05-10".to_string(),
            toks_per_sec: 42.1,
            model_id: "phi-3-mini".to_string(),
        },
        BenchmarkResult {
            date: "2026-04-10".to_string(),
            toks_per_sec: 39.8,
            model_id: "phi-3-mini".to_string(),
        },
        BenchmarkResult {
            date: "2026-03-10".to_string(),
            toks_per_sec: 41.3,
            model_id: "phi-3-mini".to_string(),
        },
    ];
    Ok(results.into_iter().take(limit).collect())
}

/// Lists all installed local models.
#[tauri::command]
pub async fn list_models() -> Result<Vec<ModelEntry>, String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    Ok(vec![
        ModelEntry {
            model_id: "phi-3-mini-4k-instruct.Q4_K_M".to_string(),
            size_mb: 2_340,
            last_used_at: Some("2026-05-13".to_string()),
            roles: vec!["chat".to_string(), "summarize".to_string()],
        },
        ModelEntry {
            model_id: "nomic-embed-text-v1.5.Q8_0".to_string(),
            size_mb: 274,
            last_used_at: Some("2026-05-12".to_string()),
            roles: vec!["embed".to_string()],
        },
    ])
}

/// Runs the hardware benchmark and returns the result.
#[tauri::command]
pub async fn run_benchmark() -> Result<BenchmarkResult, String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    Ok(BenchmarkResult {
        date: "2026-05-13".to_string(),
        toks_per_sec: 43.5,
        model_id: "phi-3-mini-4k-instruct.Q4_K_M".to_string(),
    })
}

/// Opens a file-picker dialog and imports the chosen .gguf file.
/// Returns the registered model_id.
#[tauri::command]
pub async fn import_custom_gguf(app: tauri::AppHandle, path: String) -> Result<String, String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let _ = app;
    let _ = path;
    Ok("custom-model.Q4_K_M".to_string())
}

/// Sets (or clears) the tier override. Pass `None` for Auto.
#[tauri::command]
pub async fn set_tier_override(tier: Option<u8>) -> Result<(), String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let _ = tier;
    Ok(())
}

/// Enables or disables T4 (heavy) model execution.
#[tauri::command]
pub async fn set_allow_t4(allow: bool) -> Result<(), String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let _ = allow;
    Ok(())
}

/// Enables or disables the monthly auto-benchmark cron.
#[tauri::command]
pub async fn set_re_bench_monthly(enabled: bool) -> Result<(), String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let _ = enabled;
    Ok(())
}

/// Deletes a local model from disk.
#[tauri::command]
pub async fn delete_model(model_id: String) -> Result<(), String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let _ = model_id;
    Ok(())
}

/// Sets a model's primary inference role (chat / summarize / embed / code).
#[tauri::command]
pub async fn set_model_role(model_id: String, role: String) -> Result<(), String> {
    // stub: returns canned data; backend wiring lands in S15.T17 acceptance gate
    let _ = model_id;
    let _ = role;
    Ok(())
}

/// Returns upgrade config (prompt disabled flag + deferral timestamp).
#[tauri::command]
pub async fn get_upgrade_config() -> Result<UpgradeConfig, String> {
    // stub: returns default config; backend wiring lands in S15.T17 acceptance gate
    Ok(UpgradeConfig {
        upgrade_prompt_disabled: false,
        last_upgrade_prompt_at: None,
    })
}

/// Initiates upgrade to the specified tier (0–4).
/// For T4, the caller must show a confirmation dialog.
#[tauri::command]
pub async fn upgrade_to_tier(tier: u8) -> Result<(), String> {
    // stub: logs the request; backend wiring lands in S15.T17 acceptance gate
    if tier > 4 {
        return Err("Invalid tier: must be 0–4".to_string());
    }
    eprintln!("upgrade_to_tier stub called with tier={}", tier);
    Ok(())
}

/// Disables upgrade prompts until re-enabled by the user.
#[tauri::command]
pub async fn set_upgrade_prompt_disabled(disabled: bool) -> Result<(), String> {
    // stub: logs the request; backend wiring lands in S15.T17 acceptance gate
    eprintln!(
        "set_upgrade_prompt_disabled stub called with disabled={}",
        disabled
    );
    Ok(())
}

/// Defers upgrade prompts for 30 days by updating last_upgrade_prompt_at.
#[tauri::command]
pub async fn defer_upgrade_prompt_30_days() -> Result<(), String> {
    // stub: logs the request; backend wiring lands in S15.T17 acceptance gate
    let now = Utc::now().to_rfc3339();
    eprintln!(
        "defer_upgrade_prompt_30_days stub called; next prompt after 30 days from {}",
        now
    );
    Ok(())
}
