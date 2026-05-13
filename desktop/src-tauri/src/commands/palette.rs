// ɳClaw Desktop — Command Palette Tauri command (stub)
//
// Real wiring (topics, conversations from Postgres sync) lands in S17.
// This stub returns canned topics matching the query.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind")]
pub enum PaletteResult {
  Topic { id: String, label: String },
  Conversation {
    id: String,
    label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
  },
  Setting { id: String, label: String },
  Command {
    id: String,
    label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    shortcut: Option<String>,
  },
}

/// Search for topics and conversations by query.
/// Stub implementation returns canned topics matching the query string.
/// Real implementation (S17 acceptance gate) will query Postgres for synced topics + conversations.
#[tauri::command]
pub async fn palette_search(query: String) -> Result<Vec<PaletteResult>, String> {
  let q_lower = query.to_lowercase();

  // Canned topics (stub — real topics from DB in S17)
  let topics = vec![
    ("work", "Work"),
    ("personal", "Personal"),
    ("learning", "Learning"),
    ("ai-models", "AI Models"),
    ("architecture", "Architecture"),
  ];

  // Filter by query
  let results: Vec<PaletteResult> = topics
    .into_iter()
    .filter(|(id, label)| {
      id.to_lowercase().contains(&q_lower) || label.to_lowercase().contains(&q_lower)
    })
    .map(|(id, label)| PaletteResult::Topic {
      id: id.to_string(),
      label: label.to_string(),
    })
    .collect();

  Ok(results)
}
