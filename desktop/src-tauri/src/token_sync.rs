//! T-2162: Token sync -- watches gog CLI token refreshes and syncs to server.
//! Watches ~/.config/gog/tokens/ for file changes using notify crate.
//! On change: reads token file, POSTs to server /mux/tokens/import.
//! Controlled by auto_sync_tokens in CompanionConfig.

use notify::{Event, EventKind, RecursiveMode, Watcher};
use std::path::PathBuf;
use std::sync::mpsc as std_mpsc;

/// Start watching gog token directory and sync changes to the server.
/// Blocks the current async task until cancelled.
pub async fn watch_token_refreshes(server_url: &str) {
    let token_dir = match dirs::home_dir() {
        Some(h) => h.join(".config").join("gog").join("tokens"),
        None => {
            tracing::error!("token_sync: cannot determine home directory");
            return;
        }
    };

    if !token_dir.exists() {
        tracing::info!(
            path = %token_dir.display(),
            "token_sync: token directory does not exist yet, waiting for creation"
        );
        // Wait for the directory to appear
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(10)).await;
            if token_dir.exists() {
                break;
            }
        }
    }

    tracing::info!(path = %token_dir.display(), "token_sync: watching for token changes");

    let server = server_url.to_string();

    // notify crate uses std sync channels
    let (tx, rx) = std_mpsc::channel::<notify::Result<Event>>();

    let mut watcher = match notify::recommended_watcher(tx) {
        Ok(w) => w,
        Err(e) => {
            tracing::error!("token_sync: failed to create watcher: {e}");
            return;
        }
    };

    if let Err(e) = watcher.watch(&token_dir, RecursiveMode::NonRecursive) {
        tracing::error!("token_sync: failed to watch directory: {e}");
        return;
    }

    // Process events in a blocking thread since notify uses std channels
    let handle = tokio::task::spawn_blocking(move || {
        let client = reqwest::blocking::Client::new();
        let jwt = crate::ws_client::get_stored_jwt().unwrap_or_default();

        for result in rx {
            match result {
                Ok(event) => {
                    if matches!(
                        event.kind,
                        EventKind::Create(_) | EventKind::Modify(_)
                    ) {
                        for path in &event.paths {
                            handle_token_change(path, &server, &jwt, &client);
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!("token_sync: watch error: {e}");
                }
            }
        }
    });

    // Keep the watcher alive by awaiting the blocking task
    let _ = handle.await;
}

/// Read a changed token file and POST it to the server.
fn handle_token_change(
    path: &PathBuf,
    server_url: &str,
    jwt: &str,
    client: &reqwest::blocking::Client,
) {
    let filename = match path.file_name().and_then(|f| f.to_str()) {
        Some(f) => f.to_string(),
        None => return,
    };

    // Only process .json token files
    if !filename.ends_with(".json") {
        return;
    }

    // Extract account identifier from filename (e.g., "account@gmail.com.json")
    let account = filename.trim_end_matches(".json");

    let content = match std::fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!(file = %filename, error = %e, "token_sync: failed to read token file");
            return;
        }
    };

    let token_data: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(file = %filename, error = %e, "token_sync: invalid JSON in token file");
            return;
        }
    };

    let payload = serde_json::json!({
        "account": account,
        "token_data": token_data,
        "source": "companion_sync",
    });

    let url = format!("{server_url}/mux/tokens/import");

    match client
        .post(&url)
        .header("Authorization", format!("Bearer {jwt}"))
        .json(&payload)
        .send()
    {
        Ok(resp) => {
            if resp.status().is_success() {
                tracing::info!(account = %account, "token_sync: token synced successfully");
            } else {
                tracing::warn!(
                    account = %account,
                    status = %resp.status(),
                    "token_sync: server rejected token import"
                );
            }
        }
        Err(e) => {
            tracing::warn!(account = %account, error = %e, "token_sync: failed to POST token");
        }
    }
}
