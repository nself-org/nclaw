//! Mock backends for testing — in-memory implementations of all major traits.
//!
//! Provides typed builders: `InMemoryDb::builder()`, `InMemoryLlm::builder()`, etc.
//! Use in integration tests to verify client behavior without live backends.

use crate::backend::*;
use crate::error::*;
use std::collections::HashMap;
use std::result::Result;
use std::sync::{Arc, Mutex};

// ============================================================================
// InMemoryDb
// ============================================================================

/// In-memory database — Vec<Row> store, no persistence, supports basic queries.
pub struct InMemoryDb {
    data: Arc<Mutex<Vec<Row>>>,
}

impl InMemoryDb {
    pub fn builder() -> InMemoryDbBuilder {
        InMemoryDbBuilder { rows: Vec::new() }
    }
}

pub struct InMemoryDbBuilder {
    rows: Vec<Row>,
}

impl InMemoryDbBuilder {
    pub fn with_data(mut self, rows: Vec<Row>) -> Self {
        self.rows = rows;
        self
    }

    pub fn build(self) -> InMemoryDb {
        InMemoryDb {
            data: Arc::new(Mutex::new(self.rows)),
        }
    }
}

#[async_trait::async_trait]
impl Database for InMemoryDb {
    async fn execute(&self, _sql: &str, _params: &[Value]) -> Result<u64, DbError> {
        let mut data = self.data.lock().unwrap();
        let count = data.len() as u64;
        // Stub: simulate INSERT
        data.push(HashMap::new());
        Ok(count + 1)
    }

    async fn query(&self, _sql: &str, _params: &[Value]) -> Result<Vec<Row>, DbError> {
        let data = self.data.lock().unwrap();
        Ok(data.clone())
    }

    async fn migrate(&self, _version: u32) -> Result<(), DbError> {
        Ok(())
    }

    async fn health_check(&self) -> Result<(), DbError> {
        Ok(())
    }
}

// ============================================================================
// InMemoryLlm
// ============================================================================

/// Mock LLM backend — returns canned token streams from fixture map.
pub struct InMemoryLlm {
    fixtures: Arc<Mutex<HashMap<String, Vec<String>>>>,
}

impl InMemoryLlm {
    pub fn builder() -> InMemoryLlmBuilder {
        InMemoryLlmBuilder {
            fixtures: HashMap::new(),
        }
    }
}

pub struct InMemoryLlmBuilder {
    fixtures: HashMap<String, Vec<String>>,
}

impl InMemoryLlmBuilder {
    pub fn with_fixture(mut self, prompt: String, tokens: Vec<String>) -> Self {
        self.fixtures.insert(prompt, tokens);
        self
    }

    pub fn build(self) -> InMemoryLlm {
        InMemoryLlm {
            fixtures: Arc::new(Mutex::new(self.fixtures)),
        }
    }
}

#[async_trait::async_trait]
impl LlmBackend for InMemoryLlm {
    async fn generate(&self, prompt: &str, _opts: GenOpts) -> Result<TokenStream, LlmError> {
        let fixtures = self.fixtures.lock().unwrap();
        let tokens = fixtures
            .get(prompt)
            .cloned()
            .unwrap_or_else(|| vec!["[stub-response]".into()]);
        Ok(TokenStream {
            tokens,
            finish_reason: "stop".into(),
        })
    }

    async fn embed(&self, _text: &str) -> Result<Vec<f32>, LlmError> {
        Ok(vec![0.1, 0.2, 0.3, 0.4])
    }

    fn supports_streaming(&self) -> bool {
        true
    }

    fn provider(&self) -> &str {
        "mock"
    }
}

// ============================================================================
// InMemorySync
// ============================================================================

/// No-op sync engine — records calls, simulates sync without side effects.
pub struct InMemorySync {
    calls: Arc<Mutex<Vec<String>>>,
}

impl InMemorySync {
    pub fn builder() -> InMemorySyncBuilder {
        InMemorySyncBuilder { calls: Vec::new() }
    }

    pub fn get_calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }
}

pub struct InMemorySyncBuilder {
    calls: Vec<String>,
}

impl InMemorySyncBuilder {
    pub fn build(self) -> InMemorySync {
        InMemorySync {
            calls: Arc::new(Mutex::new(self.calls)),
        }
    }
}

#[async_trait::async_trait]
impl SyncEngine for InMemorySync {
    async fn push(&self, changes: &[Change]) -> Result<Vec<Conflict>, SyncError> {
        let mut calls = self.calls.lock().unwrap();
        calls.push(format!("push({} changes)", changes.len()));
        Ok(Vec::new())
    }

    async fn pull(&self) -> Result<Vec<Change>, SyncError> {
        let mut calls = self.calls.lock().unwrap();
        calls.push("pull".into());
        Ok(Vec::new())
    }

    async fn sync(&self) -> Result<SyncState, SyncError> {
        let mut calls = self.calls.lock().unwrap();
        calls.push("sync".into());
        Ok(SyncState {
            synced_count: 0,
            conflicts_resolved: 0,
            next_sync_version: 1,
        })
    }

    async fn resolve_conflict(
        &self,
        _conflict: &Conflict,
        _strategy: MergeStrategy,
    ) -> Result<(), SyncError> {
        Ok(())
    }
}

// ============================================================================
// InMemoryVault
// ============================================================================

/// HashMap-based vault — non-persistent, safe for testing.
pub struct InMemoryVault {
    secrets: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl InMemoryVault {
    pub fn builder() -> InMemoryVaultBuilder {
        InMemoryVaultBuilder {
            secrets: HashMap::new(),
        }
    }
}

pub struct InMemoryVaultBuilder {
    secrets: HashMap<String, Vec<u8>>,
}

impl InMemoryVaultBuilder {
    pub fn with_secret(mut self, key: String, value: Vec<u8>) -> Self {
        self.secrets.insert(key, value);
        self
    }

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

// ============================================================================
// NoopMux + NoopPlugin
// ============================================================================

/// Pass-through mux — returns fixture values, no routing.
pub struct NoopMux;

#[async_trait::async_trait]
impl Mux for NoopMux {
    async fn classify(&self, _content: &str) -> Result<Classification, MuxError> {
        Ok(Classification {
            category: "stub".into(),
            confidence: 0.9,
            tags: vec!["test".into()],
        })
    }

    async fn extract_entities(&self, _content: &str) -> Result<Entities, MuxError> {
        Ok(Entities {
            emails: vec!["test@example.com".into()],
            urls: vec!["http://example.com".into()],
            mentions: vec![],
            phone_numbers: vec![],
        })
    }

    async fn route(&self, _content: &str, _context: &str) -> Result<Route, MuxError> {
        Ok(Route {
            handler: "default".into(),
            priority: 1,
            metadata: HashMap::new(),
        })
    }
}

/// Stub plugin — responds to init/execute without side effects.
pub struct NoopPlugin {
    name: String,
}

impl NoopPlugin {
    pub fn new(name: &str) -> Self {
        NoopPlugin { name: name.into() }
    }
}

#[async_trait::async_trait]
impl Plugin for NoopPlugin {
    fn name(&self) -> &str {
        &self.name
    }

    fn version(&self) -> &str {
        "0.1.0"
    }

    async fn init(&mut self, _config: &PluginConfig) -> Result<(), PluginError> {
        Ok(())
    }

    async fn execute(&self, _capability: &str, input: &Value) -> Result<Value, PluginError> {
        Ok(input.clone())
    }

    async fn shutdown(&self) -> Result<(), PluginError> {
        Ok(())
    }

    async fn health_check(&self) -> Result<(), PluginError> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_in_memory_db_builder() {
        let db = InMemoryDb::builder()
            .with_data(vec![HashMap::new(), HashMap::new()])
            .build();
        let rows = db.query("SELECT *", &[]).await.unwrap();
        assert_eq!(rows.len(), 2);
    }

    #[tokio::test]
    async fn test_in_memory_llm_fixtures() {
        let llm = InMemoryLlm::builder()
            .with_fixture("hello".into(), vec!["world".into()])
            .build();
        let stream = llm
            .generate(
                "hello",
                GenOpts {
                    model: "mock".into(),
                    max_tokens: 10,
                    temperature: 0.7,
                    top_p: 0.9,
                    stop_sequences: vec![],
                },
            )
            .await
            .unwrap();
        assert_eq!(stream.tokens, vec!["world"]);
    }

    #[tokio::test]
    async fn test_in_memory_sync_call_tracking() {
        let sync = InMemorySync::builder().build();
        sync.push(&[]).await.unwrap();
        sync.pull().await.unwrap();
        let calls = sync.get_calls();
        assert!(calls.iter().any(|c| c.contains("push")));
        assert!(calls.iter().any(|c| c == "pull"));
    }

    #[tokio::test]
    async fn test_in_memory_vault_secret_storage() {
        let vault = InMemoryVault::builder()
            .with_secret("key1".into(), b"secret1".to_vec())
            .build();
        let val = vault.get("key1").await.unwrap();
        assert_eq!(val, b"secret1");
        vault.delete("key1").await.unwrap();
        assert!(vault.get("key1").await.is_err());
    }

    #[tokio::test]
    async fn test_noop_plugin_stub() {
        let mut plugin = NoopPlugin::new("test-plugin");
        plugin
            .init(&PluginConfig {
                settings: HashMap::new(),
                secrets: HashMap::new(),
            })
            .await
            .unwrap();
        plugin.health_check().await.unwrap();
        plugin.shutdown().await.unwrap();
    }
}
