//! Vault sync — fetch encrypted envelopes for this device from the nSelf backend

use crate::error::CoreError;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Encrypted envelope metadata fetched from server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultEnvelope {
    pub record_id: Uuid,
    pub envelope_ciphertext: Vec<u8>,
    pub envelope_nonce: Vec<u8>,
}

/// Fetch all vault envelopes for a device.
///
/// Server filters envelopes by device_id and returns only those this device
/// has access to. Each envelope can be decrypted with the device's keypair.
pub async fn fetch_envelopes(
    server_url: &str,
    jwt: &str,
    device_id: Uuid,
) -> Result<Vec<VaultEnvelope>, CoreError> {
    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/vault/v1/records?device_id={}", server_url, device_id))
        .bearer_auth(jwt)
        .send()
        .await
        .map_err(|e| CoreError::Other(format!("sync request failed: {}", e)))?;

    if !resp.status().is_success() {
        return Err(CoreError::Other(format!(
            "sync: HTTP {}",
            resp.status()
        )));
    }

    resp.json()
        .await
        .map_err(|e| CoreError::Other(format!("sync parse response: {}", e)))
}
