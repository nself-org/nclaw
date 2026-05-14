//! OS keychain integration for storing device secrets.
//!
//! Provides cross-platform access to:
//! - macOS Keychain
//! - Windows DPAPI (via keyring crate)
//! - Linux Secret Service (via keyring crate)
//!
//! All secrets are base64-encoded before storage to handle binary data gracefully.

use crate::error::{CoreError, VaultError};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;

const SERVICE: &str = "org.nself.nclaw";

/// Store a secret in the OS keychain, base64-encoded.
///
/// On macOS, this uses Keychain.app. On Windows, it uses DPAPI.
/// On Linux, it uses the freedesktop Secret Service.
pub fn store_secret(account: &str, value: &[u8]) -> Result<(), CoreError> {
    let entry = keyring::Entry::new(SERVICE, account).map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!(
            "keychain entry creation failed: {}",
            e
        )))
    })?;
    let encoded = STANDARD.encode(value);
    entry.set_password(&encoded).map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!(
            "keychain store failed: {}",
            e
        )))
    })
}

/// Retrieve a secret from the OS keychain, base64-decoded.
pub fn fetch_secret(account: &str) -> Result<Vec<u8>, CoreError> {
    let entry = keyring::Entry::new(SERVICE, account).map_err(|e| {
        CoreError::Vault(VaultError::SecretNotFound(format!(
            "keychain entry creation failed: {}",
            e
        )))
    })?;
    let pw = entry.get_password().map_err(|e| {
        CoreError::Vault(VaultError::SecretNotFound(format!(
            "keychain fetch failed: {}",
            e
        )))
    })?;
    STANDARD
        .decode(pw.as_bytes())
        .map_err(|e| CoreError::Vault(VaultError::InvalidFormat))
}

/// Delete a secret from the OS keychain.
pub fn delete_secret(account: &str) -> Result<(), CoreError> {
    let entry = keyring::Entry::new(SERVICE, account).map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!(
            "keychain entry creation failed: {}",
            e
        )))
    })?;
    entry.delete_credential().map_err(|e| {
        CoreError::Vault(VaultError::EncryptionFailed(format!(
            "keychain delete failed: {}",
            e
        )))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Skip keychain tests on CI (env var NCLAW_SKIP_KEYCHAIN=1)
    fn should_skip_keychain_tests() -> bool {
        std::env::var("NCLAW_SKIP_KEYCHAIN").is_ok()
    }

    #[test]
    fn test_store_and_fetch_roundtrip() {
        if should_skip_keychain_tests() {
            return;
        }

        let account = "test_account";
        let value = b"test secret value";

        store_secret(account, value).expect("store should succeed");
        let fetched = fetch_secret(account).expect("fetch should succeed");

        assert_eq!(fetched, value);

        // Cleanup
        let _ = delete_secret(account);
    }

    #[test]
    fn test_store_binary_data() {
        if should_skip_keychain_tests() {
            return;
        }

        let account = "test_binary";
        let value = &[0u8, 1, 2, 3, 255, 254, 253];

        store_secret(account, value).expect("store should succeed");
        let fetched = fetch_secret(account).expect("fetch should succeed");

        assert_eq!(fetched, value);

        let _ = delete_secret(account);
    }

    #[test]
    fn test_delete_secret() {
        if should_skip_keychain_tests() {
            return;
        }

        let account = "test_delete";
        let value = b"value to delete";

        store_secret(account, value).expect("store should succeed");
        delete_secret(account).expect("delete should succeed");

        // Fetching after delete should fail
        let result = fetch_secret(account);
        assert!(result.is_err());
    }

    #[test]
    fn test_fetch_nonexistent_secret() {
        if should_skip_keychain_tests() {
            return;
        }

        let result = fetch_secret("nonexistent_account_12345");
        assert!(result.is_err());
    }
}
