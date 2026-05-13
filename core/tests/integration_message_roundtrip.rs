//! Integration tests: message round-trip through mock Db / Sync / Vault / Llm / Mux / Plugin.

use libnclaw::backend::{Change, GenOpts, MergeStrategy, PluginConfig, Value};
use libnclaw::testing::{
    InMemoryDb, InMemoryLlm, InMemorySync, InMemoryVault, NoopMux, NoopPlugin,
};
use libnclaw::types::{Message, MessageContent, MessageMetadata, MessageRole};
use std::collections::HashMap;
use uuid::Uuid;

fn make_message() -> Message {
    Message {
        id: Uuid::new_v4(),
        conversation_id: Uuid::new_v4(),
        role: MessageRole::User,
        content: MessageContent::Text("hello from test".into()),
        created_at: chrono::Utc::now(),
        model: None,
        tool_calls: vec![],
        metadata: MessageMetadata::default(),
    }
}

// 1. Vault set/get round-trip
#[tokio::test]
async fn test_vault_set_get_roundtrip() {
    let vault = InMemoryVault::builder().build();
    vault.set("user_token", b"demo-token").await.unwrap();
    let got = vault.get("user_token").await.unwrap();
    assert_eq!(got, b"demo-token");
}

// 2. Vault delete removes key
#[tokio::test]
async fn test_vault_delete_removes_key() {
    let vault = InMemoryVault::builder()
        .with_secret("k".into(), b"v".to_vec())
        .build();
    vault.delete("k").await.unwrap();
    assert!(vault.get("k").await.is_err());
}

// 3. Vault keys() lists stored keys
#[tokio::test]
async fn test_vault_keys_lists_all() {
    let vault = InMemoryVault::builder()
        .with_secret("a".into(), b"1".to_vec())
        .with_secret("b".into(), b"2".to_vec())
        .build();
    let keys = vault.keys().await.unwrap();
    assert!(keys.contains(&"a".to_string()));
    assert!(keys.contains(&"b".to_string()));
}

// 4. Db execute inserts a row; query retrieves it
#[tokio::test(flavor = "multi_thread")]
async fn test_db_execute_and_query() {
    let db = InMemoryDb::builder().build();
    let affected = db
        .execute(
            "INSERT INTO messages (id, content) VALUES ($1, $2)",
            &[Value::Text("msg-1".into()), Value::Text("hello".into())],
        )
        .await
        .unwrap();
    assert!(affected >= 1);
    let rows = db.query("SELECT * FROM messages", &[]).await.unwrap();
    assert!(!rows.is_empty());
}

// 5. Db health_check passes
#[tokio::test]
async fn test_db_health_check() {
    let db = InMemoryDb::builder().build();
    db.health_check().await.unwrap();
}

// 6. Sync push records the call; get_calls returns it
#[tokio::test(flavor = "multi_thread")]
async fn test_sync_push_records_call() {
    let msg = make_message();
    let body = match &msg.content {
        MessageContent::Text(t) => t.clone(),
        _ => "".into(),
    };
    let sync = InMemorySync::builder().build();
    let change = Change {
        entity_type: "message".into(),
        entity_id: msg.id.to_string(),
        operation: "insert".into(),
        timestamp: 0,
        data: Value::Text(body),
    };
    sync.push(&[change]).await.unwrap();
    let calls = sync.get_calls();
    assert!(calls.iter().any(|c| c.contains("push")));
}

// 7. Llm generate_stream returns fixture tokens
#[tokio::test]
async fn test_llm_generate_returns_tokens() {
    let llm = InMemoryLlm::builder()
        .with_fixture("test prompt".into(), vec!["tok1".into(), "tok2".into()])
        .build();
    let stream = llm
        .generate(
            "test prompt",
            GenOpts {
                model: "mock".into(),
                max_tokens: 20,
                temperature: 0.5,
                top_p: 1.0,
                stop_sequences: vec![],
            },
        )
        .await
        .unwrap();
    assert_eq!(stream.tokens, vec!["tok1", "tok2"]);
    assert_eq!(stream.finish_reason, "stop");
}

// 8. Mux classify returns a non-empty label
#[tokio::test]
async fn test_mux_classify_non_empty_label() {
    let msg = make_message();
    let body = match &msg.content {
        MessageContent::Text(t) => t.clone(),
        _ => "".into(),
    };
    let mux = NoopMux;
    let result = mux.classify(&body).await.unwrap();
    assert!(!result.category.is_empty());
}

// 9. Plugin init → execute → shutdown lifecycle
#[tokio::test]
async fn test_plugin_lifecycle_smoke() {
    let mut plugin = NoopPlugin::new("test-plugin");
    let config = PluginConfig {
        settings: HashMap::new(),
        secrets: HashMap::new(),
    };
    plugin.init(&config).await.unwrap();
    let input = Value::Text("ping".into());
    plugin.execute("noop", &input).await.unwrap();
    plugin.health_check().await.unwrap();
    plugin.shutdown().await.unwrap();
}
