//! Shared type definitions for nClaw client-server communication.
//!
//! These types are used on both the client (Swift/Kotlin/WASM) and server
//! (nself-claw plugin) sides of the nClaw protocol. Changes here require
//! coordinated client and server updates.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// =============================================================================
// Conversation and Message types
// =============================================================================

/// A conversation between a user and an AI assistant.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub message_count: u32,
    pub is_pinned: bool,
    pub branch_parent_id: Option<Uuid>,
}

/// A single message in a conversation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub role: MessageRole,
    pub content: MessageContent,
    pub created_at: DateTime<Utc>,
    pub model: Option<String>,
    pub tool_calls: Vec<ToolCall>,
    pub metadata: MessageMetadata,
}

/// The role of a message sender.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum MessageRole {
    User,
    Assistant,
    System,
    Tool,
}

/// The content of a message — text or multimodal.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum MessageContent {
    Text(String),
    Parts(Vec<ContentPart>),
}

/// A single part of a multimodal message.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentPart {
    Text { text: String },
    Image { url: String, mime_type: String },
    File { url: String, name: String, mime_type: String },
    ToolResult { tool_call_id: String, content: String, is_error: bool },
}

/// Metadata attached to a message.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MessageMetadata {
    /// Token counts if available.
    pub input_tokens: Option<u32>,
    pub output_tokens: Option<u32>,
    /// Latency in milliseconds from request to first token.
    pub first_token_ms: Option<u32>,
    /// Whether this message was loaded from cache.
    pub from_cache: bool,
}

// =============================================================================
// Tool call types
// =============================================================================

/// A tool call made by the AI assistant.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub tool_name: String,
    pub input: serde_json::Value,
    pub status: ToolCallStatus,
    pub result: Option<ToolCallResult>,
}

/// The status of a tool call.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ToolCallStatus {
    Running,
    Success,
    Error,
}

/// The result of a completed tool call.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallResult {
    pub content: String,
    pub is_error: bool,
    pub duration_ms: u32,
}

// =============================================================================
// User / Auth types
// =============================================================================

/// Authenticated user identity.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserIdentity {
    pub id: Uuid,
    pub email: String,
    pub display_name: Option<String>,
    pub role: UserRole,
}

/// User roles within nClaw.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum UserRole {
    Owner,
    Member,
    Guest,
}

// =============================================================================
// Server info
// =============================================================================

/// Server capability advertisement returned by /health or /info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerInfo {
    pub version: String,
    pub nself_version: Option<String>,
    pub features: Vec<String>,
    pub plugins_loaded: Vec<String>,
    pub encryption_required: bool,
}
