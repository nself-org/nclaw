//! Protocol definitions for nClaw client-server communication.
//!
//! Defines request/response types for all nClaw API endpoints.
//! These are the wire-format types sent over HTTP/WebSocket.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::types::{Conversation, Message, ServerInfo};

// =============================================================================
// Chat / streaming
// =============================================================================

/// A chat request sent to the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    /// The conversation to continue. `None` creates a new conversation.
    pub conversation_id: Option<Uuid>,
    /// The user's message content.
    pub content: String,
    /// Override the model for this request. Server picks default if `None`.
    pub model: Option<String>,
    /// System prompt override. Server uses default if `None`.
    pub system: Option<String>,
    /// Whether to stream the response.
    #[serde(default = "default_true")]
    pub stream: bool,
}

fn default_true() -> bool {
    true
}

/// A non-streaming chat response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatResponse {
    pub conversation_id: Uuid,
    pub message: Message,
    pub status: ChatStatus,
}

/// The terminal status of a chat turn.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ChatStatus {
    /// The turn completed successfully.
    Done,
    /// The model hit a stop sequence or max tokens.
    StopSequence,
    /// A server-side error occurred.
    Error,
}

// =============================================================================
// Streaming events (Server-Sent Events)
// =============================================================================

/// A single server-sent event in a streaming chat response.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum StreamEvent {
    /// A delta of assistant text.
    TextDelta {
        conversation_id: Uuid,
        delta: String,
    },
    /// A tool call is starting.
    ToolCallStart {
        conversation_id: Uuid,
        tool_call_id: String,
        tool_name: String,
    },
    /// A tool call has completed.
    ToolCallEnd {
        conversation_id: Uuid,
        tool_call_id: String,
        /// The tool result content.
        result: String,
        is_error: bool,
    },
    /// The stream has ended successfully.
    Done {
        conversation_id: Uuid,
        message_id: Uuid,
    },
    /// A stream-level error.
    Error { code: String, message: String },
}

// =============================================================================
// Conversation list
// =============================================================================

/// Response for `GET /conversations`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationListResponse {
    pub conversations: Vec<Conversation>,
    pub total: u32,
    pub page: u32,
    pub per_page: u32,
    pub has_more: bool,
}

// =============================================================================
// Message list
// =============================================================================

/// Response for `GET /conversations/{id}/messages`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageListResponse {
    pub messages: Vec<Message>,
    pub conversation_id: Uuid,
    pub total: u32,
}

// =============================================================================
// API error
// =============================================================================

/// A structured API error returned in non-2xx responses.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiError {
    pub code: ApiErrorCode,
    pub message: String,
    /// Optional extra context (e.g. which field failed validation).
    pub details: Option<serde_json::Value>,
}

/// Machine-readable error codes.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ApiErrorCode {
    Unauthorized,
    Forbidden,
    NotFound,
    RateLimited,
    InvalidRequest,
    InternalError,
    PluginNotReady,
    ModelUnavailable,
    ContextLengthExceeded,
}

// =============================================================================
// Health / info
// =============================================================================

/// Response for `GET /health`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub ok: bool,
    pub info: ServerInfo,
}

// =============================================================================
// Device pairing (QR-code flow)
// =============================================================================

/// Step 1 — mobile app sends this to initiate pairing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairRequest {
    /// The device's X25519 public key (base64url-encoded).
    pub device_public_key: String,
    pub device_name: String,
    pub platform: DevicePlatform,
}

/// The platform of the device being paired.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DevicePlatform {
    Ios,
    Android,
    Macos,
    Web,
}

/// Step 2 — server responds with its public key and a session token.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairResponse {
    /// The server's X25519 public key (base64url-encoded).
    pub server_public_key: String,
    /// Short-lived JWT granting access from this device.
    pub session_token: String,
    /// Seconds until `session_token` expires.
    pub expires_in: u32,
}
