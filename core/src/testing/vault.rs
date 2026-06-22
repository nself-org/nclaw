//! `InMemoryVault` — HashMap-based secret store for testing.
//!
//! Non-persistent, safe for testing. Supports all `Vault` trait operations
//! (get, set, delete, keys, rotate_keys) without touching the macOS Keychain
//! or any system secret store.

use crate::backend::*;
use crate::error::*;
use std::collections::HashMap;
use std::result::Result;
use std::sync::{Arc, Mutex};

/// HashMap-based vault — non-persistent, safe for testing.
pub struct InMemoryVault {
    secrets: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl InMemoryVault {
    /// Create a builder for `InMemoryVault` with optional pre-seeded secrets.
    pub fn builder() -> InMemoryVaultBuilder {
        InMemoryVaultBuilder {
            secrets: HashMap::new(),
        }
    }
}

/// Builder for `InMemoryVault` — pre-seed secrets before building.
pub struct InMemoryVaultBuilder {
    secrets: HashMap<String, Vec<u8>>,
}

impl InMemoryVaultBuilder {
    /// Pre-seed a secret `key` → `value` byte mapping.
    pub fn with_secret(mut self, key: String, value: Vec<u8>) -> Self {
        self.secrets.insert(key, value);
        self
    }

    /// Build the `InMemoryVault` with all pre-seeded secrets.
    pub fn build(self) -> InMemoryVault {
        InMemoryVault {
            secrets: Arc::new(Mutex::new(self.secrets)),
        }
    }
}

#[async_trait::async_trait]
impl Vault for InMemoryVault {
    async fn set(&self, key: &str, value: &[u8]) -> Result<(), VaultError> {
        let mut secrets = self.secrets.lock().unwrap();
        secrets.insert(key.into(), value.to_vec());
        Ok(())
    }

    async fn get(&self, key: &str) -> Result<Vec<u8>, VaultError> {
        let secrets = self.secrets.lock().unwrap();
        secrets
            .get(key)
            .cloned()
            .ok_or(VaultError::SecretNotFound(key.into()))
    }

    async fn delete(&self, key: &str) -> Result<(), VaultError> {
        let mut secrets = self.secrets.lock().unwrap();
        secrets.remove(key);
        Ok(())
    }

    async fn keys(&self) -> Result<Vec<String>, VaultError> {
        let secrets = self.secrets.lock().unwrap();
        Ok(secrets.keys().cloned().collect())
    }

    async fn rotate_keys(&self) -> Result<(), VaultError> {
        Ok(())
    }
}
