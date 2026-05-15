use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Topic {
    pub id: String,
    pub path: String,
    pub name: String,
    pub archived: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub topics: Vec<Topic>,
    pub matched_message_topics: Vec<String>,
}

/// Return all non-archived topics ordered by path.
/// Not yet available: S17 sync acceptance gate wires real Postgres ltree query.
#[tauri::command]
pub async fn list_topics() -> Result<Vec<Topic>, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S17-DB-topics"
    })
    .to_string())
}

/// Move a topic to a new parent path (drag-to-reorder).
/// Not yet available: S17 sync acceptance gate wires real ltree ops.
#[tauri::command]
pub async fn move_topic(_from_id: String, _to_parent_path: String) -> Result<(), String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S17-DB-topics"
    })
    .to_string())
}

/// Search topics by name and return topics that contain matching messages.
/// Not yet available: S17 wires MeiliSearch full-text search.
#[tauri::command]
pub async fn search(_query: String) -> Result<SearchResult, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S17-search"
    })
    .to_string())
}
