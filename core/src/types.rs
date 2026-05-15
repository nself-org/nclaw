//! Shared type definitions for nClaw client-server communication.
//!
//! These types are used on both the client (Swift/Kotlin/WASM) and server
//! (nself-claw plugin) sides of the nClaw protocol. Changes here require
//! coordinated client and server updates.
//!
//! When feature `frb-export` is enabled, types are annotated for
//! flutter_rust_bridge codegen to produce Dart FFI bindings.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[cfg(feature = "frb-export")]
use flutter_rust_bridge::frb;
#[cfg(feature = "ts-export")]
use ts_rs::TS;

// =============================================================================
// Conversation and Message types
// =============================================================================

/// A conversation between a user and an AI assistant.
#[cfg_attr(feature = "frb-export", frb)]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "ts-export", derive(TS))]
#[cfg_attr(
    feature = "ts-export",
    ts(export, export_to = "../../../app/lib/bindings/")
)]
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
#[cfg_attr(feature = "frb-export", frb)]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "ts-export", derive(TS))]
#[cfg_attr(
    feature = "ts-export",
    ts(export, export_to = "../../../app/lib/bindings/")
)]
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

impl MessageContent {
    /// Return the plain-text representation of this content, if the message is
    /// purely textual. Returns `Some(&str)` for `Text(_)`, `None` for any
    /// multimodal `Parts(_)` (callers must walk the parts themselves to extract
    /// per-part text).
    pub fn as_text(&self) -> Option<&str> {
        match self {
            MessageContent::Text(s) => Some(s.as_str()),
            MessageContent::Parts(_) => None,
        }
    }
}

/// A single part of a multimodal message.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentPart {
    Text {
        text: String,
    },
    Image {
        url: String,
        mime_type: String,
    },
    File {
        url: String,
        name: String,
        mime_type: String,
    },
    ToolResult {
        tool_call_id: String,
        content: String,
        is_error: bool,
    },
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
#[cfg_attr(feature = "frb-export", frb)]
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

// =============================================================================
// Memory / Knowledge Graph types
// =============================================================================

/// A topic or cluster in the user's knowledge graph.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "ts-export", derive(TS))]
#[cfg_attr(
    feature = "ts-export",
    ts(export, export_to = "../../../app/lib/bindings/")
)]
pub struct Topic {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub entity_count: u32,
    pub conversation_count: u32,
}

/// A persistent memory or fact extracted from conversations.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "ts-export", derive(TS))]
#[cfg_attr(
    feature = "ts-export",
    ts(export, export_to = "../../../app/lib/bindings/")
)]
pub struct Memory {
    pub id: Uuid,
    pub user_id: Uuid,
    pub topic_id: Option<Uuid>,
    pub content: String,
    pub memory_type: MemoryType,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub confidence: f32,
    pub sources: Vec<String>,
}

/// The kind of memory stored.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MemoryType {
    Fact,
    Preference,
    Goal,
    Event,
    Relationship,
    Rule,
}

/// A named entity (person, place, org) in the knowledge graph.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entity {
    pub id: Uuid,
    pub user_id: Uuid,
    pub topic_id: Option<Uuid>,
    pub name: String,
    pub entity_type: String,
    pub attributes: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub mention_count: u32,
}

/// A plugin or tool available to the assistant.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Plugin {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: Option<String>,
    pub enabled: bool,
    pub installed_at: Option<DateTime<Utc>>,
    pub config: serde_json::Value,
}

/// A document stored for RAG or retrieval.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub content: String,
    pub mime_type: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub is_indexed: bool,
    pub embedding: Option<Vec<f32>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_serialization_roundtrip() {
        let msg = Message {
            id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            role: MessageRole::Assistant,
            content: MessageContent::Text("Hello".to_string()),
            created_at: Utc::now(),
            model: Some("claude-3".to_string()),
            tool_calls: vec![],
            metadata: MessageMetadata {
                input_tokens: Some(100),
                output_tokens: Some(50),
                first_token_ms: Some(250),
                from_cache: false,
            },
        };
        let json = serde_json::to_string(&msg).expect("serialize");
        let parsed: Message = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(parsed.id, msg.id);
        assert_eq!(parsed.role, MessageRole::Assistant);
    }

    #[test]
    fn test_content_part_serialization() {
        let part = ContentPart::Image {
            url: "https://example.com/img.png".to_string(),
            mime_type: "image/png".to_string(),
        };
        let json = serde_json::to_string(&part).expect("serialize");
        assert!(json.contains("image"));
        let parsed: ContentPart = serde_json::from_str(&json).expect("deserialize");
        if let ContentPart::Image { url, .. } = parsed {
            assert_eq!(url, "https://example.com/img.png");
        }
    }

    #[test]
    fn test_memory_serialization() {
        let mem = Memory {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            topic_id: Some(Uuid::new_v4()),
            content: "User prefers dark mode".to_string(),
            memory_type: MemoryType::Preference,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            confidence: 0.95,
            sources: vec!["msg_123".to_string()],
        };
        let json = serde_json::to_string(&mem).expect("serialize");
        let parsed: Memory = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(parsed.memory_type, MemoryType::Preference);
        assert!(parsed.confidence > 0.9);
    }

    #[test]
    fn test_entity_serialization() {
        let ent = Entity {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            topic_id: None,
            name: "Alice".to_string(),
            entity_type: "person".to_string(),
            attributes: serde_json::json!({"role": "friend"}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            mention_count: 5,
        };
        let json = serde_json::to_string(&ent).expect("serialize");
        let parsed: Entity = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(parsed.name, "Alice");
        assert_eq!(parsed.mention_count, 5);
    }
}
