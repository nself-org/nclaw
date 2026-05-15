// chat.rs — Tauri command for chat message handling.
// Real LlmBackend wiring lands in S15.T17 acceptance gate.

#[derive(serde::Deserialize, serde::Serialize, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

/// Send a chat message sequence to the local or remote LLM backend.
/// Returns the assistant reply as a string.
///
/// Not yet available: S15.T17 wires the real streaming LlmBackend path.
#[tauri::command]
pub async fn stream_chat(_messages: Vec<ChatMessage>) -> Result<String, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S15-T17"
    })
    .to_string())
}
