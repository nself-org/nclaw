//! Backend trait abstractions for libnclaw core.
//!
//! Defines async trait interfaces for LLM, DB, Sync, Vault, Mux, and Plugin backends.
//! Traits are object-safe (`dyn Backend` patterns) using boxed futures.

use crate::error::{DbError, LlmError, MuxError, PluginError, Result, SyncError, VaultError};
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;

type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

// ============================================================================
// LLM Backend
// ============================================================================

/// LLM provider backend — handles generation, embeddings, and streaming.
pub trait LlmBackend: Send + Sync {
    fn generate(&self, prompt: &str, opts: GenOpts) -> BoxFuture<Result<TokenStream, LlmError>>;
    fn embed(&self, text: &str) -> BoxFuture<Result<Vec<f32>, LlmError>>;
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

pub trait Database: Send + Sync {
    fn execute(&self, sql: &str, params: &[Value]) -> BoxFuture<Result<u64, DbError>>;
    fn query(&self, sql: &str, params: &[Value]) -> BoxFuture<Result<Vec<Row>, DbError>>;
    fn migrate(&self, version: u32) -> BoxFuture<Result<(), DbError>>;
    fn health_check(&self) -> BoxFuture<Result<(), DbError>>;
}

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

pub trait SyncEngine: Send + Sync {
    fn push(&self, changes: &[Change]) -> BoxFuture<Result<Vec<Conflict>, SyncError>>;
    fn pull(&self) -> BoxFuture<Result<Vec<Change>, SyncError>>;
    fn sync(&self) -> BoxFuture<Result<SyncState, SyncError>>;
    fn resolve_conflict(
        &self,
        conflict: &Conflict,
        strategy: MergeStrategy,
    ) -> BoxFuture<Result<(), SyncError>>;
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

pub trait Vault: Send + Sync {
    fn set(&self, key: &str, value: &[u8]) -> BoxFuture<Result<(), VaultError>>;
    fn get(&self, key: &str) -> BoxFuture<Result<Vec<u8>, VaultError>>;
    fn delete(&self, key: &str) -> BoxFuture<Result<(), VaultError>>;
    fn keys(&self) -> BoxFuture<Result<Vec<String>, VaultError>>;
    fn rotate_keys(&self) -> BoxFuture<Result<(), VaultError>>;
}

// ============================================================================
// Mux Backend
// ============================================================================

pub trait Mux: Send + Sync {
    fn classify(&self, content: &str) -> BoxFuture<Result<Classification, MuxError>>;
    fn extract_entities(&self, content: &str) -> BoxFuture<Result<Entities, MuxError>>;
    fn route(&self, content: &str, context: &str) -> BoxFuture<Result<Route, MuxError>>;
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

pub trait Plugin: Send + Sync {
    fn name(&self) -> &str;
    fn version(&self) -> &str;
    fn init(&mut self, config: &PluginConfig) -> BoxFuture<Result<(), PluginError>>;
    fn execute(&self, capability: &str, input: &Value) -> BoxFuture<Result<Value, PluginError>>;
    fn shutdown(&self) -> BoxFuture<Result<(), PluginError>>;
    fn health_check(&self) -> BoxFuture<Result<(), PluginError>>;
}

pub struct PluginConfig {
    pub settings: HashMap<String, Value>,
    pub secrets: HashMap<String, Vec<u8>>,
}
