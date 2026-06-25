//! Integration tests for libnclaw::testing — mock backend builders.
//!
//! Exercises `InMemoryDb`, `InMemoryLlm`, `InMemorySync`, `InMemoryVault`,
//! and `NoopPlugin` via their public builder APIs.

use libnclaw::backend::{GenOpts, LlmBackend, Database, SyncEngine, Vault};
use libnclaw::testing::{InMemoryDb, InMemoryLlm, InMemorySync, InMemoryVault, NoopPlugin};
use std::collections::HashMap;

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
    use libnclaw::backend::{Plugin, PluginConfig};
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
