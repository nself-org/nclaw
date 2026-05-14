//! Unified Data Access Layer (DAL) for nClaw local DB.
//!
//! Implemented by both desktop (pglite/embedded-postgres) and mobile (sqlite-vec) engines.
//! Concrete implementations land in T05b (sqlx/pglite) and T06b (rusqlite/sqlite-vec).
//!
//! The trait is fully async (`async_trait`) and object-safe via `Send + Sync` bounds.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde_json;
use uuid::Uuid;

use crate::error::CoreError;
use crate::types::{Conversation, Memory, Message, Topic};

/// Primary DAL trait — the only interface concrete DB engines expose to the rest of core.
///
/// All write operations are idempotent where noted. Implementors MUST NOT assume any
/// particular transaction boundary across multiple trait calls — callers are responsible
/// for sequencing.
#[async_trait]
pub trait NclawDb: Send + Sync {
    // ------------------------------------------------------------------
    // Topics
    // ------------------------------------------------------------------

    /// Create a new topic. `path` is the ltree path (e.g. `"work.projects.nself"`).
    /// Returns the created [`Topic`].
    async fn create_topic(
        &self,
        path: &str,
        title: &str,
        parent: Option<Uuid>,
    ) -> Result<Topic, CoreError>;

    /// Fetch a single topic by ID. Returns `None` if not found.
    async fn get_topic(&self, id: Uuid) -> Result<Option<Topic>, CoreError>;

    /// List topics, optionally filtered to direct children of `parent`.
    /// If `parent` is `None`, returns root-level topics.
    async fn list_topics(&self, parent: Option<Uuid>) -> Result<Vec<Topic>, CoreError>;

    /// Rename a topic's display title (does not alter ltree path).
    async fn rename_topic(&self, id: Uuid, new_title: &str) -> Result<(), CoreError>;

    /// Mark a topic archived (soft-delete). Preserves data.
    async fn archive_topic(&self, id: Uuid) -> Result<(), CoreError>;

    /// Permanently delete a topic and all child data. IRREVERSIBLE.
    async fn delete_topic(&self, id: Uuid) -> Result<(), CoreError>;

    /// Re-parent a topic under `new_parent`. If `new_parent` is `None`, moves to root.
    async fn move_topic(&self, id: Uuid, new_parent: Option<Uuid>) -> Result<(), CoreError>;

    // ------------------------------------------------------------------
    // Messages
    // ------------------------------------------------------------------

    /// Persist a new message. Idempotent on `msg.id` (upsert by PK).
    async fn insert_message(&self, msg: &Message) -> Result<(), CoreError>;

    /// Fetch a single message by ID. Returns `None` if not found.
    async fn get_message(&self, id: Uuid) -> Result<Option<Message>, CoreError>;

    /// List messages within a conversation, newest-first, with pagination.
    async fn list_messages_in_conversation(
        &self,
        conversation_id: Uuid,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Message>, CoreError>;

    /// Patch a message's metadata JSON (merge, not replace).
    async fn update_message_metadata(
        &self,
        id: Uuid,
        metadata: serde_json::Value,
    ) -> Result<(), CoreError>;

    /// Permanently delete a message.
    async fn delete_message(&self, id: Uuid) -> Result<(), CoreError>;

    // ------------------------------------------------------------------
    // Conversations
    // ------------------------------------------------------------------

    /// Create a new conversation record. Returns the created [`Conversation`].
    async fn create_conversation(
        &self,
        user_id: Uuid,
        title: Option<&str>,
    ) -> Result<Conversation, CoreError>;

    /// Fetch a conversation by ID.
    async fn get_conversation(&self, id: Uuid) -> Result<Option<Conversation>, CoreError>;

    /// List conversations for a user, newest-first.
    async fn list_conversations(
        &self,
        user_id: Uuid,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<Conversation>, CoreError>;

    // ------------------------------------------------------------------
    // Memories
    // ------------------------------------------------------------------

    /// Upsert a memory record (insert or update by `mem.id`).
    async fn upsert_memory(&self, mem: &Memory) -> Result<(), CoreError>;

    /// Fetch a memory by ID.
    async fn get_memory(&self, id: Uuid) -> Result<Option<Memory>, CoreError>;

    /// List memories of a given type (e.g. `"fact"`, `"preference"`), newest-first.
    async fn list_memories_by_kind(&self, kind: &str, limit: u32)
        -> Result<Vec<Memory>, CoreError>;

    /// Set a memory's expiry so it is excluded from retrieval after `valid_until`.
    async fn invalidate_memory(
        &self,
        id: Uuid,
        valid_until: DateTime<Utc>,
    ) -> Result<(), CoreError>;

    /// Permanently delete a memory.
    async fn delete_memory(&self, id: Uuid) -> Result<(), CoreError>;

    // ------------------------------------------------------------------
    // Entities
    // ------------------------------------------------------------------

    /// Upsert a named entity by `(kind, name)`. Returns the entity's UUID.
    async fn upsert_entity(
        &self,
        kind: &str,
        name: &str,
        metadata: serde_json::Value,
    ) -> Result<Uuid, CoreError>;

    /// Look up an entity's UUID by `(kind, name)`. Returns `None` if not found.
    async fn get_entity(&self, kind: &str, name: &str) -> Result<Option<Uuid>, CoreError>;

    // ------------------------------------------------------------------
    // Embeddings
    // ------------------------------------------------------------------

    /// Store a vector embedding for any entity.
    ///
    /// `target_kind` identifies the owning table (`"message"`, `"memory"`, `"topic_summary"`).
    /// Returns the embedding row UUID.
    async fn insert_embedding(
        &self,
        target_kind: &str,
        target_id: Uuid,
        model_id: &str,
        dimension: u32,
        embedding: Vec<f32>,
    ) -> Result<Uuid, CoreError>;

    // ------------------------------------------------------------------
    // Sync queue
    // ------------------------------------------------------------------

    /// Enqueue an outbound sync event.
    async fn enqueue_sync_event(
        &self,
        event_id: Uuid,
        payload: serde_json::Value,
    ) -> Result<(), CoreError>;

    /// Dequeue up to `limit` pending sync events. Marks them in-flight.
    async fn pop_due_sync_events(
        &self,
        limit: u32,
    ) -> Result<Vec<(Uuid, serde_json::Value)>, CoreError>;

    // ------------------------------------------------------------------
    // Health
    // ------------------------------------------------------------------

    /// Verify that the DB connection (or embedded engine) is reachable.
    async fn health_check(&self) -> Result<(), CoreError>;
}
