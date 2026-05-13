// chat.rs — stub Tauri command for chat message handling.
// Real LlmBackend wiring lands in S15.T17 acceptance gate.

#[derive(serde::Deserialize, serde::Serialize, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

/// Stub command: returns a canned reply echoing the last user message.
/// S15.T17 replaces this body with real streaming via LlmBackend.
#[tauri::command]
pub async fn stream_chat(messages: Vec<ChatMessage>) -> Result<String, String> {
    let last = messages
        .last()
        .map(|m| m.content.as_str())
        .unwrap_or("(empty)");
    Ok(format!("(stub response) You said: {}", last))
}
