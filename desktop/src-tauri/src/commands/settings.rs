// ɳClaw Desktop — Settings Tauri commands (stub)
//
// Real persistence wires in S18 (vault) and S17 (sync acceptance gates).
// These stubs return canned data so the frontend can develop against real shapes.

use serde_json::Value;

// ---- Canned defaults -------------------------------------------------------

fn canned_settings() -> Value {
    serde_json::json!({
        "provider": {
            "id": "local-llamacpp",
            "base_url": "http://127.0.0.1:8080",
            "api_key_masked": ""
        },
        "model": {
            "chat": "",
            "summarizer": "",
            "embedder": "",
            "code": ""
        },
        "vault": {
            "paired": false,
            "backend": "macOS Keychain"
        },
        "sync": {
            "server_url": "",
            "license_key_masked": ""
        },
        "advanced": {
            "log_level": "info",
            "telemetry": true,
            "check_updates": true
        }
    })
}

// ---- Commands --------------------------------------------------------------

/// Return a single setting value by key.
/// Key must be one of: "provider" | "model" | "vault" | "sync" | "advanced".
/// Returns the full section object. Real storage wires in S18.
#[tauri::command]
pub async fn get_setting(key: String) -> Result<Value, String> {
    let all = canned_settings();
    match all.get(&key) {
        Some(v) => Ok(v.clone()),
        None => Err(format!("unknown setting key: {key}")),
    }
}

/// Return all settings in a single call (used by the frontend on mount).
#[tauri::command]
pub async fn get_all_settings() -> Result<Value, String> {
    Ok(canned_settings())
}

/// Persist a setting section. Key/value mirror the `get_setting` shape.
/// Real encryption + keychain storage wires in S18.
#[tauri::command]
pub async fn set_setting(_key: String, _value: Value) -> Result<(), String> {
    // Stub: accept writes silently.
    // S18 will persist to encrypted store + OS keychain as appropriate.
    Ok(())
}

// ---- Vault -----------------------------------------------------------------

/// Re-pair this device's encryption key with the OS keychain.
/// Destructive: generates new device keypair — existing synced data needs re-pull.
/// Wires to real vault implementation in S18.
#[tauri::command]
pub async fn vault_repair_device() -> Result<(), String> {
    // Stub: succeed immediately. Real impl generates X25519 keypair + stores in keychain.
    Ok(())
}

// ---- Sync ------------------------------------------------------------------

/// Test connectivity to the nSelf sync server.
/// Returns true on HTTP 200 from `{url}/api/health`, false otherwise.
/// Wires to real HTTP client in S17.
#[tauri::command]
pub async fn test_sync_connection(url: String, key: String) -> Result<bool, String> {
    // Stub: return success when a URL is provided.
    let _ = key; // used for auth header in S17
    if url.is_empty() {
        return Err("server URL is required".to_string());
    }
    // Real impl: reqwest GET {url}/api/health with Authorization: Bearer {key}
    Ok(true)
}
// Note: list_models is provided by commands::local_ai::list_models (S15 stub).
