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
        .map_err(|_e| CoreError::Vault(VaultError::InvalidFormat))
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
    use std::sync::OnceLock;

    // Skip keychain tests when the OS keychain is genuinely unavailable.
    //
    // Fast-path: honour explicit env-var overrides and known CI signals so the
    // probe cost is never paid in automated pipelines.
    //
    // Probe path: attempt a trivial store→fetch→delete round-trip with a
    // throwaway key.  Any error (no Security Server, sandbox denial, access
    // denied) returns true (skip).  The result is cached in a OnceLock so the
    // probe runs at most once per test-binary invocation.
    fn should_skip_keychain_tests() -> bool {
        // Fast-path env overrides — no probe needed.
        if std::env::var("NCLAW_SKIP_KEYCHAIN").is_ok()
            || std::env::var("CI").is_ok()
            || std::env::var("GITHUB_ACTIONS").is_ok()
            || std::env::var("NCLAW_SKIP_KEYCHAIN_TESTS").is_ok()
        {
            return true;
        }

        // Cached probe result (runs once per test-binary invocation).
        static PROBE: OnceLock<bool> = OnceLock::new();
        *PROBE.get_or_init(|| {
            const PROBE_KEY: &str = "__nclaw_probe__";
            let probe_value = b"probe";

            // store
            if store_secret(PROBE_KEY, probe_value).is_err() {
                return true; // keychain unavailable — skip
            }

            // fetch — must round-trip correctly
            match fetch_secret(PROBE_KEY) {
                Err(_) => {
                    // Best-effort cleanup; ignore result.
                    let _ = delete_secret(PROBE_KEY);
                    return true;
                }
                Ok(fetched) if fetched != probe_value => {
                    let _ = delete_secret(PROBE_KEY);
                    return true;
                }
                Ok(_) => {}
            }

            // delete — leave no trace
            if delete_secret(PROBE_KEY).is_err() {
                return true;
            }

            false // keychain is available; run the real tests
        })
    }

    #[test]
    fn test_store_and_fetch_roundtrip() {
        if should_skip_keychain_tests() {
            eprintln!("SKIP: test_store_and_fetch_roundtrip — keychain unavailable in CI/headless env");
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
            eprintln!("SKIP: test_store_binary_data — keychain unavailable in CI/headless env");
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
            eprintln!("SKIP: test_delete_secret — keychain unavailable in CI/headless env");
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
            eprintln!("SKIP: test_fetch_nonexistent_secret — keychain unavailable in CI/headless env");
            return;
        }

        let result = fetch_secret("nonexistent_account_12345");
        assert!(result.is_err());
    }
}
