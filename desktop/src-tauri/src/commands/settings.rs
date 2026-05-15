// ɳClaw Desktop — Settings Tauri commands
//
// Real persistence wires in S18 (vault) and S17 (sync acceptance gates).
// Until those sprints land, every command returns a typed NotImplemented error
// so the frontend shows a clear "not yet available" state instead of
// silently returning canned data that masks missing real data.

use serde_json::Value;

// ---- Commands --------------------------------------------------------------

/// Return a single setting value by key.
/// Key must be one of: "provider" | "model" | "vault" | "sync" | "advanced".
/// Not yet available: S18 vault acceptance gate wires real encrypted storage.
#[tauri::command]
pub async fn get_setting(_key: String) -> Result<Value, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}

/// Return all settings in a single call (used by the frontend on mount).
/// Not yet available: S18 vault acceptance gate wires real encrypted storage.
#[tauri::command]
pub async fn get_all_settings() -> Result<Value, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}

/// Persist a setting section. Key/value mirror the `get_setting` shape.
/// Not yet available: S18 vault acceptance gate wires real encrypted keychain storage.
#[tauri::command]
pub async fn set_setting(_key: String, _value: Value) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}

// ---- Vault -----------------------------------------------------------------
// `vault_repair_device` lives in commands::vault (canonical home for vault ops).

// ---- Sync ------------------------------------------------------------------

/// Test connectivity to the nSelf sync server.
/// Returns true on HTTP 200 from `{url}/api/health`, false otherwise.
/// Not yet available: S17 sync acceptance gate wires real reqwest HTTP client.
#[tauri::command]
pub async fn test_sync_connection(url: String, _key: String) -> Result<bool, String> {
    if url.is_empty() {
        return Err("server URL is required".to_string());
    }
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S17-sync"
    })
    .to_string())
}
// Note: list_models is provided by commands::local_ai::list_models (awaiting S15-T17).
