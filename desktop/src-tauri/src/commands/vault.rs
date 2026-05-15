//! Tauri commands for vault operations — device pairing, registration, revocation.
//! Not yet available: S18 invoke bridge wires real nclaw-core vault module.

/// Return device pairing status from the local keychain.
/// Not yet available: S18 vault acceptance gate wires real keychain read + server ping.
#[tauri::command]
pub async fn vault_status() -> Result<serde_json::Value, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}

/// Re-pair this device: regenerate X25519 keypair, register with server, persist device_id.
/// Not yet available: S18 vault acceptance gate wires real registration::register.
#[tauri::command]
pub async fn vault_repair_device() -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}

/// Revoke a previously registered device from the sync server.
/// Not yet available: S18 vault acceptance gate wires real revocation::revoke.
#[tauri::command]
pub async fn vault_revoke_device(_device_id: String) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}

/// Trigger an immediate sync: fetch envelopes from server and decrypt each.
/// Not yet available: S18 vault acceptance gate wires real sync::fetch_envelopes.
#[tauri::command]
pub async fn vault_sync_now() -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S18-vault"
    })
    .to_string())
}
