//! Device revocation flow — revoke a device and cascade wipe encrypted envelopes

use crate::error::CoreError;
use uuid::Uuid;

/// Revoke a device on the nSelf vault server.
///
/// This endpoint requires a valid JWT and the device_id to revoke.
/// Server cascades: deletes the device record, marks all its envelopes for deletion,
/// and notifies other devices that they may need to re-sync.
pub async fn revoke(server_url: &str, jwt: &str, device_id: Uuid) -> Result<(), CoreError> {
    let client = reqwest::Client::new();
    let resp = client
        .delete(format!("{}/vault/v1/devices/{}", server_url, device_id))
        .bearer_auth(jwt)
        .send()
        .await
        .map_err(|e| CoreError::Other(format!("revoke request failed: {}", e)))?;

    if !resp.status().is_success() {
        return Err(CoreError::Other(format!(
            "revoke: HTTP {}",
            resp.status()
        )));
    }

    Ok(())
}
