//! Smoke tests for the NclawDb DAL trait and VectorSearch trait.
//!
//! Uses `InMemoryNclawDb` — a Vec-backed mock that proves the trait surface compiles
//! and behaves correctly at the interface level. No real DB involved.
//!
//! Concrete sqlx/rusqlite implementations are validated in T05b/T06b.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use libnclaw::db::dal::NclawDb;
use libnclaw::db::vector::{VectorHit, VectorSearch};
use libnclaw::error::CoreError;
use libnclaw::types::{
    Conversation, Memory, MemoryType, Message, MessageContent, MessageMetadata, MessageRole, Topic,
};
use serde_json::json;
use std::sync::Mutex;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// In-memory mock implementation
// ---------------------------------------------------------------------------

struct InMemoryNclawDb {
    topics: Mutex<Vec<Topic>>,
    messages: Mutex<Vec<Message>>,
    memories: Mutex<Vec<Memory>>,
    conversations: Mutex<Vec<Conversation>>,
    entities: Mutex<Vec<(String, String, Uuid, serde_json::Value)>>, // (kind, name, id, meta)
    sync_queue: Mutex<Vec<(Uuid, serde_json::Value)>>,
}

impl InMemoryNclawDb {
    fn new() -> Self {
        Self {
            topics: Mutex::new(vec![]),
            messages: Mutex::new(vec![]),
            memories: Mutex::new(vec![]),
            conversations: Mutex::new(vec![]),
            entities: Mutex::new(vec![]),
            sync_queue: Mutex::new(vec![]),
        }
    }
}

#[async_trait]
impl NclawDb for InMemoryNclawDb {
    // Topics -------------------------------------------------------------------

    async fn create_topic(
        &self,
        _path: &str,
        title: &str,
        _parent: Option<Uuid>,
    ) -> Result<Topic, CoreError> {
        let now = Utc::now();
        let t = Topic {
            id: Uuid::new_v4(),
            user_id: Uuid::nil(),
            title: title.to_string(),
            description: None,
            created_at: now,
            updated_at: now,
            entity_count: 0,
            conversation_count: 0,
        };
        self.topics.lock().unwrap().push(t.clone());
        Ok(t)
    }

    async fn get_topic(&self, id: Uuid) -> Result<Option<Topic>, CoreError> {
        Ok(self
            .topics
            .lock()
            .unwrap()
            .iter()
            .find(|t| t.id == id)
            .cloned())
    }

    async fn list_topics(&self, _parent: Option<Uuid>) -> Result<Vec<Topic>, CoreError> {
        Ok(self.topics.lock().unwrap().clone())
    }

    async fn rename_topic(&self, id: Uuid, new_title: &str) -> Result<(), CoreError> {
        let mut lock = self.topics.lock().unwrap();
        match lock.iter_mut().find(|t| t.id == id) {
            Some(t) => {
                t.title = new_title.to_string();
                Ok(())
            }
            None => Err(CoreError::Other(format!("topic {} not found", id))),
        }
    }

    async fn archive_topic(&self, _id: Uuid) -> Result<(), CoreError> {
        Ok(()) // archived flag not on Topic struct yet — no-op in mock
    }

    async fn delete_topic(&self, id: Uuid) -> Result<(), CoreError> {
        self.topics.lock().unwrap().retain(|t| t.id != id);
        Ok(())
    }

    async fn move_topic(&self, _id: Uuid, _new_parent: Option<Uuid>) -> Result<(), CoreError> {
        Ok(()) // path mutation deferred to real impl
    }

    // Messages -----------------------------------------------------------------

    async fn insert_message(&self, msg: &Message) -> Result<(), CoreError> {
        let mut lock = self.messages.lock().unwrap();
        lock.retain(|m| m.id != msg.id); // upsert by PK
        lock.push(msg.clone());
        Ok(())
    }

    async fn get_message(&self, id: Uuid) -> Result<Option<Message>, CoreError> {
        Ok(self
            .messages
            .lock()
            .unwrap()
            .iter()
            .find(|m| m.id == id)
            .cloned())
    }

    async fn list_messages_in_conversation(
        &self,
        conversation_id: Uuid,
        limit: u32,
        _offset: u32,
    ) -> Result<Vec<Message>, CoreError> {
        let lock = self.messages.lock().unwrap();
        let msgs: Vec<Message> = lock
            .iter()
            .filter(|m| m.conversation_id == conversation_id)
            .take(limit as usize)
            .cloned()
            .collect();
        Ok(msgs)
    }

    async fn update_message_metadata(
        &self,
        _id: Uuid,
        _metadata: serde_json::Value,
    ) -> Result<(), CoreError> {
        Ok(()) // metadata merge deferred to real impl
    }

    async fn delete_message(&self, id: Uuid) -> Result<(), CoreError> {
        self.messages.lock().unwrap().retain(|m| m.id != id);
        Ok(())
    }

    // Conversations ------------------------------------------------------------

    async fn create_conversation(
        &self,
        user_id: Uuid,
        title: Option<&str>,
    ) -> Result<Conversation, CoreError> {
        let now = Utc::now();
        let c = Conversation {
            id: Uuid::new_v4(),
            user_id,
            title: title.map(|s| s.to_string()),
            created_at: now,
            updated_at: now,
            message_count: 0,
            is_pinned: false,
            branch_parent_id: None,
        };
        self.conversations.lock().unwrap().push(c.clone());
        Ok(c)
    }

    async fn get_conversation(&self, id: Uuid) -> Result<Option<Conversation>, CoreError> {
        Ok(self
            .conversations
            .lock()
            .unwrap()
            .iter()
            .find(|c| c.id == id)
            .cloned())
    }

    async fn list_conversations(
        &self,
        user_id: Uuid,
        limit: u32,
        _offset: u32,
    ) -> Result<Vec<Conversation>, CoreError> {
        let lock = self.conversations.lock().unwrap();
        Ok(lock
            .iter()
            .filter(|c| c.user_id == user_id)
            .take(limit as usize)
            .cloned()
            .collect())
    }

    // Memories -----------------------------------------------------------------

    async fn upsert_memory(&self, mem: &Memory) -> Result<(), CoreError> {
        let mut lock = self.memories.lock().unwrap();
        lock.retain(|m| m.id != mem.id);
        lock.push(mem.clone());
        Ok(())
    }

    async fn get_memory(&self, id: Uuid) -> Result<Option<Memory>, CoreError> {
        Ok(self
            .memories
            .lock()
            .unwrap()
            .iter()
            .find(|m| m.id == id)
            .cloned())
    }

    async fn list_memories_by_kind(
        &self,
        _kind: &str,
        limit: u32,
    ) -> Result<Vec<Memory>, CoreError> {
        let lock = self.memories.lock().unwrap();
        Ok(lock.iter().take(limit as usize).cloned().collect())
    }

    async fn invalidate_memory(
        &self,
        _id: Uuid,
        _valid_until: DateTime<Utc>,
    ) -> Result<(), CoreError> {
        Ok(()) // expiry field deferred to real impl
    }

    async fn delete_memory(&self, id: Uuid) -> Result<(), CoreError> {
        self.memories.lock().unwrap().retain(|m| m.id != id);
        Ok(())
    }

    // Entities -----------------------------------------------------------------

    async fn upsert_entity(
        &self,
        kind: &str,
        name: &str,
        metadata: serde_json::Value,
    ) -> Result<Uuid, CoreError> {
        let mut lock = self.entities.lock().unwrap();
        if let Some(existing) = lock.iter().find(|(k, n, _, _)| k == kind && n == name) {
            return Ok(existing.2);
        }
        let id = Uuid::new_v4();
        lock.push((kind.to_string(), name.to_string(), id, metadata));
        Ok(id)
    }

    async fn get_entity(&self, kind: &str, name: &str) -> Result<Option<Uuid>, CoreError> {
        let lock = self.entities.lock().unwrap();
        Ok(lock
            .iter()
            .find(|(k, n, _, _)| k == kind && n == name)
            .map(|(_, _, id, _)| *id))
    }

    // Embeddings ---------------------------------------------------------------

    async fn insert_embedding(
        &self,
        _target_kind: &str,
        _target_id: Uuid,
        _model_id: &str,
        _dimension: u32,
        _embedding: Vec<f32>,
    ) -> Result<Uuid, CoreError> {
        Ok(Uuid::new_v4()) // row ID — real impl writes to np_embeddings
    }

    // Sync queue ---------------------------------------------------------------

    async fn enqueue_sync_event(
        &self,
        event_id: Uuid,
        payload: serde_json::Value,
    ) -> Result<(), CoreError> {
        self.sync_queue.lock().unwrap().push((event_id, payload));
        Ok(())
    }

    async fn pop_due_sync_events(
        &self,
        limit: u32,
    ) -> Result<Vec<(Uuid, serde_json::Value)>, CoreError> {
        let mut lock = self.sync_queue.lock().unwrap();
        let n = (limit as usize).min(lock.len());
        Ok(lock.drain(..n).collect())
    }

    // Health -------------------------------------------------------------------

    async fn health_check(&self) -> Result<(), CoreError> {
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// In-memory VectorSearch mock
// ---------------------------------------------------------------------------

struct InMemoryVectorSearch;

#[async_trait]
impl VectorSearch for InMemoryVectorSearch {
    async fn vector_search(
        &self,
        _owner_kind: &str,
        _query_embedding: &[f32],
        k: u32,
    ) -> Result<Vec<VectorHit>, CoreError> {
        // Return k synthetic hits with descending similarity for shape verification.
        let hits: Vec<VectorHit> = (0..k)
            .map(|i| VectorHit {
                target_id: Uuid::new_v4(),
                similarity: 1.0 - (i as f32 * 0.1),
                model_id: "text-embedding-3-small".to_string(),
            })
            .collect();
        Ok(hits)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn create_and_get_topic() {
    let db = InMemoryNclawDb::new();
    let t = db
        .create_topic("work.projects.nself", "nSelf", None)
        .await
        .unwrap();
    assert_eq!(t.title, "nSelf");

    let fetched = db.get_topic(t.id).await.unwrap().expect("topic must exist");
    assert_eq!(fetched.id, t.id);
}

#[tokio::test]
async fn insert_and_list_messages() {
    let db = InMemoryNclawDb::new();
    let conv_id = Uuid::new_v4();

    let msg = Message {
        id: Uuid::new_v4(),
        conversation_id: conv_id,
        role: MessageRole::User,
        content: MessageContent::Text("Hello nClaw".to_string()),
        created_at: Utc::now(),
        model: None,
        tool_calls: vec![],
        metadata: MessageMetadata::default(),
    };

    db.insert_message(&msg).await.unwrap();

    let msgs = db
        .list_messages_in_conversation(conv_id, 10, 0)
        .await
        .unwrap();
    assert_eq!(msgs.len(), 1);
    assert_eq!(msgs[0].id, msg.id);
}

#[tokio::test]
async fn upsert_and_recall_memory() {
    let db = InMemoryNclawDb::new();
    let user_id = Uuid::new_v4();
    let now = Utc::now();

    let mem = Memory {
        id: Uuid::new_v4(),
        user_id,
        topic_id: None,
        content: "User prefers dark mode".to_string(),
        memory_type: MemoryType::Preference,
        created_at: now,
        updated_at: now,
        confidence: 0.95,
        sources: vec!["conv-abc".to_string()],
    };

    db.upsert_memory(&mem).await.unwrap();

    let fetched = db
        .get_memory(mem.id)
        .await
        .unwrap()
        .expect("memory must exist");
    assert_eq!(fetched.content, "User prefers dark mode");
}

#[tokio::test]
async fn vector_search_returns_k_hits() {
    let vs = InMemoryVectorSearch;
    let query = vec![0.1_f32; 1536];
    let hits = vs.vector_search("message", &query, 5).await.unwrap();
    assert_eq!(hits.len(), 5);
    // Results are ordered by descending similarity.
    assert!(hits[0].similarity >= hits[4].similarity);
}

#[tokio::test]
async fn health_check_passes() {
    let db = InMemoryNclawDb::new();
    db.health_check().await.unwrap();
}
