//! Device registration flow — register a new device with the nSelf vault server

use crate::error::CoreError;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Device registration request payload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceRegistration {
    pub device_pubkey: Vec<u8>,
    pub label: String,
    pub platform: String,
}

/// Server response after successful device registration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceRegistered {
    pub device_id: Uuid,
}

/// Register a new device with the nSelf vault server.
///
/// This endpoint requires a valid JWT. The server stores the device pubkey
/// and assigns a device_id that the client uses for future vault sync.
pub async fn register(
    server_url: &str,
    jwt: &str,
    reg: &DeviceRegistration,
) -> Result<DeviceRegistered, CoreError> {
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{}/vault/v1/devices", server_url))
        .bearer_auth(jwt)
        .json(reg)
        .send()
        .await
        .map_err(|e| CoreError::Other(format!("register request failed: {}", e)))?;

    if !resp.status().is_success() {
        return Err(CoreError::Other(format!(
            "register: HTTP {}",
            resp.status()
        )));
    }

    resp.json().await
        .map_err(|e| CoreError::Other(format!("register parse response: {}", e)))
}
