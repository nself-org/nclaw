//! Tauri command stubs for vault operations — device pairing, registration, revocation

#[tauri::command]
pub async fn vault_status() -> Result<serde_json::Value, String> {
    // Stub: real impl reads device_id from keychain, checks server status
    Ok(serde_json::json!({
        "paired": false,
        "backend": "macOS Keychain",
        "device_id": null,
        "last_sync": null,
    }))
}

#[tauri::command]
pub async fn vault_repair_device() -> Result<(), String> {
    // Stub: real impl regenerates keypair, calls registration::register,
    // persists device_id to keychain
    Ok(())
}

#[tauri::command]
pub async fn vault_revoke_device(device_id: String) -> Result<(), String> {
    // Stub: calls revocation::revoke via the server
    let _ = device_id;
    Ok(())
}

#[tauri::command]
pub async fn vault_sync_now() -> Result<(), String> {
    // Stub: calls sync::fetch_envelopes and decrypts each envelope
    Ok(())
}
