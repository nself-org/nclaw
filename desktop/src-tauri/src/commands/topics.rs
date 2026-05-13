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
/// Stub — real DB wiring lands in S17 sync acceptance gate.
#[tauri::command]
pub async fn list_topics() -> Result<Vec<Topic>, String> {
    Ok(vec![
        Topic {
            id: "t-work".into(),
            path: "work".into(),
            name: "Work".into(),
            archived: false,
        },
        Topic {
            id: "t-work-projects".into(),
            path: "work.projects".into(),
            name: "Projects".into(),
            archived: false,
        },
        Topic {
            id: "t-work-projects-nself".into(),
            path: "work.projects.nself".into(),
            name: "nSelf".into(),
            archived: false,
        },
        Topic {
            id: "t-personal".into(),
            path: "personal".into(),
            name: "Personal".into(),
            archived: false,
        },
    ])
}

/// Move a topic to a new parent path (drag-to-reorder).
/// Stub — persists in S17 when ltree ops are wired.
#[tauri::command]
pub async fn move_topic(_from_id: String, _to_parent_path: String) -> Result<(), String> {
    Ok(())
}

/// Search topics by name and return topics that contain matching messages.
/// Stub — full-text search wires to MeiliSearch in S17.
#[tauri::command]
pub async fn search(query: String) -> Result<SearchResult, String> {
    let all = list_topics().await?;
    let q = query.to_lowercase();
    let topics = all
        .into_iter()
        .filter(|t| t.name.to_lowercase().contains(&q))
        .collect();
    Ok(SearchResult {
        topics,
        matched_message_topics: vec![],
    })
}
