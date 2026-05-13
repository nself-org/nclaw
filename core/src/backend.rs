//! Backend trait abstractions for libnclaw core.
//!
//! Defines async trait interfaces for LLM, DB, Sync, Vault, Mux, and Plugin backends.
//! Traits are object-safe (`dyn Backend` patterns) using async_trait.

use crate::error::{DbError, LlmError, MuxError, PluginError, SyncError, VaultError};
use std::collections::HashMap;
use std::result::Result;

// ============================================================================
// LLM Backend
// ============================================================================

/// LLM provider backend — handles generation, embeddings, and streaming.
#[async_trait::async_trait]
pub trait LlmBackend: Send + Sync {
    async fn generate(&self, prompt: &str, opts: GenOpts) -> Result<TokenStream, LlmError>;
    async fn embed(&self, text: &str) -> Result<Vec<f32>, LlmError>;
    fn supports_streaming(&self) -> bool;
    fn provider(&self) -> &str;
}

pub struct GenOpts {
    pub model: String,
    pub max_tokens: usize,
    pub temperature: f32,
    pub top_p: f32,
    pub stop_sequences: Vec<String>,
}

pub struct TokenStream {
    pub tokens: Vec<String>,
    pub finish_reason: String,
}

// ============================================================================
// Database Backend
// ============================================================================

#[async_trait::async_trait]
pub trait Database: Send + Sync {
    async fn execute(&self, sql: &str, params: &[Value]) -> Result<u64, DbError>;
    async fn query(&self, sql: &str, params: &[Value]) -> Result<Vec<Row>, DbError>;
    async fn migrate(&self, version: u32) -> Result<(), DbError>;
    async fn health_check(&self) -> Result<(), DbError>;
}

#[derive(Clone)]
pub enum Value {
    Text(String),
    Integer(i64),
    Float(f64),
    Bytes(Vec<u8>),
    Null,
}

pub type Row = HashMap<String, Value>;

// ============================================================================
// Sync Engine
// ============================================================================

#[async_trait::async_trait]
pub trait SyncEngine: Send + Sync {
    async fn push(&self, changes: &[Change]) -> Result<Vec<Conflict>, SyncError>;
    async fn pull(&self) -> Result<Vec<Change>, SyncError>;
    async fn sync(&self) -> Result<SyncState, SyncError>;
    async fn resolve_conflict(
        &self,
        conflict: &Conflict,
        strategy: MergeStrategy,
    ) -> Result<(), SyncError>;
}

pub struct Change {
    pub entity_type: String,
    pub entity_id: String,
    pub operation: String,
    pub timestamp: u64,
    pub data: Value,
}

pub struct Conflict {
    pub entity_type: String,
    pub entity_id: String,
    pub local: Value,
    pub remote: Value,
}

#[derive(Clone, Copy)]
pub enum MergeStrategy {
    LocalWins,
    RemoteWins,
    Combine,
}

pub struct SyncState {
    pub synced_count: usize,
    pub conflicts_resolved: usize,
    pub next_sync_version: u64,
}

// ============================================================================
// Vault Backend
// ============================================================================

#[async_trait::async_trait]
pub trait Vault: Send + Sync {
    async fn set(&self, key: &str, value: &[u8]) -> Result<(), VaultError>;
    async fn get(&self, key: &str) -> Result<Vec<u8>, VaultError>;
    async fn delete(&self, key: &str) -> Result<(), VaultError>;
    async fn keys(&self) -> Result<Vec<String>, VaultError>;
    async fn rotate_keys(&self) -> Result<(), VaultError>;
}

// ============================================================================
// Mux Backend
// ============================================================================

#[async_trait::async_trait]
pub trait Mux: Send + Sync {
    async fn classify(&self, content: &str) -> Result<Classification, MuxError>;
    async fn extract_entities(&self, content: &str) -> Result<Entities, MuxError>;
    async fn route(&self, content: &str, context: &str) -> Result<Route, MuxError>;
}

pub struct Classification {
    pub category: String,
    pub confidence: f32,
    pub tags: Vec<String>,
}

pub struct Entities {
    pub emails: Vec<String>,
    pub urls: Vec<String>,
    pub mentions: Vec<String>,
    pub phone_numbers: Vec<String>,
}

pub struct Route {
    pub handler: String,
    pub priority: u32,
    pub metadata: HashMap<String, String>,
}

// ============================================================================
// Plugin Backend
// ============================================================================

#[async_trait::async_trait]
pub trait Plugin: Send + Sync {
    fn name(&self) -> &str;
    fn version(&self) -> &str;
    async fn init(&mut self, config: &PluginConfig) -> Result<(), PluginError>;
    async fn execute(&self, capability: &str, input: &Value) -> Result<Value, PluginError>;
    async fn shutdown(&self) -> Result<(), PluginError>;
    async fn health_check(&self) -> Result<(), PluginError>;
}

pub struct PluginConfig {
    pub settings: HashMap<String, Value>,
    pub secrets: HashMap<String, Vec<u8>>,
}
