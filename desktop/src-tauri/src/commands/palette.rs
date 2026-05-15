// ɳClaw Desktop — Command Palette Tauri command.
//
// Returns `NotImplemented` until ticket S17 wires the real Postgres + MeiliSearch
// query path. The error envelope is verified by the not_implemented_guard tests
// so the frontend can rely on a stable error shape pre-S17.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind")]
pub enum PaletteResult {
    Topic {
        id: String,
        label: String,
    },
    Conversation {
        id: String,
        label: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        description: Option<String>,
    },
    Setting {
        id: String,
        label: String,
    },
    Command {
        id: String,
        label: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        shortcut: Option<String>,
    },
}

/// Search for topics and conversations by query.
///
/// Returns a `NotImplemented` JSON envelope (`{"error":"NotImplemented","awaiting":"S17-search"}`)
/// until ticket S17 wires the real Postgres + MeiliSearch query path.
#[tauri::command]
pub async fn palette_search(_query: String) -> Result<Vec<PaletteResult>, String> {
    Err(serde_json::json!({
        "error": "NotImplemented",
        "awaiting": "S17-search"
    })
    .to_string())
}
