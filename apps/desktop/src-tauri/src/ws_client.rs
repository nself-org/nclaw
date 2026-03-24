//! T-2161: WebSocket client connecting to claw server.
//! Persistent connection with exponential backoff reconnect.
//! JWT auth via system keychain (keyring crate). On first launch, opens browser for pairing.
//! WS handshake sends JWT in Authorization header. On 401: re-pair flow.

use futures_util::{SinkExt, StreamExt};
use tauri::Manager;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::http::Request;
use tokio_tungstenite::{connect_async, tungstenite};

const INITIAL_BACKOFF_MS: u64 = 1000;
const MAX_BACKOFF_MS: u64 = 60_000;
const KEYRING_SERVICE: &str = "org.nself.companion";
const KEYRING_USER: &str = "jwt";

/// Outbound message sender type, shared with other modules.
pub type WsSender = mpsc::UnboundedSender<String>;

/// Retrieve stored JWT from system keychain.
pub fn get_stored_jwt() -> Option<String> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER).ok()?;
    entry.get_password().ok()
}

/// Store JWT in system keychain.
pub fn store_jwt(token: &str) -> Result<(), String> {
    let entry =
        keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER).map_err(|e| format!("{e}"))?;
    entry
        .set_password(token)
        .map_err(|e| format!("keyring store failed: {e}"))
}

/// Clear stored JWT from system keychain.
pub fn clear_jwt() -> Result<(), String> {
    let entry =
        keyring::Entry::new(KEYRING_SERVICE, KEYRING_USER).map_err(|e| format!("{e}"))?;
    entry
        .delete_credential()
        .map_err(|e| format!("keyring delete failed: {e}"))
}

/// Open the pairing URL in the user's default browser.
/// The server returns a JWT after the user approves the pairing request.
async fn initiate_pairing(server_url: &str) -> Result<String, String> {
    let device_id = uuid::Uuid::new_v4().to_string();
    let pair_url = format!("{server_url}/claw/companion/pair?device_id={device_id}");

    tracing::info!("Opening browser for pairing: {pair_url}");
    open::that(&pair_url).map_err(|e| format!("failed to open browser: {e}"))?;

    // Poll the pairing endpoint until the user approves
    let client = reqwest::Client::new();
    let poll_url = format!("{server_url}/claw/companion/pair/status?device_id={device_id}");

    for _ in 0..120 {
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;

        let resp = client
            .get(&poll_url)
            .send()
            .await
            .map_err(|e| format!("poll failed: {e}"))?;

        if resp.status().is_success() {
            let body: serde_json::Value = resp
                .json()
                .await
                .map_err(|e| format!("parse failed: {e}"))?;

            if let Some(token) = body["token"].as_str() {
                tracing::info!("Pairing successful");
                store_jwt(token)?;
                return Ok(token.to_string());
            }
        }
    }

    Err("Pairing timed out after 4 minutes".into())
}

/// Get a valid JWT, initiating pairing if needed.
async fn ensure_jwt(server_url: &str) -> Result<String, String> {
    if let Some(jwt) = get_stored_jwt() {
        return Ok(jwt);
    }
    initiate_pairing(server_url).await
}

/// Run the WebSocket client with auto-reconnect and JWT auth.
pub async fn run_ws_client(server_url: &str, app_handle: tauri::AppHandle) {
    let mut backoff = INITIAL_BACKOFF_MS;

    loop {
        // Get JWT (from keychain or pairing flow)
        let jwt = match ensure_jwt(server_url).await {
            Ok(t) => t,
            Err(e) => {
                tracing::error!("Failed to get JWT: {e}");
                tokio::time::sleep(std::time::Duration::from_millis(backoff)).await;
                backoff = (backoff * 2).min(MAX_BACKOFF_MS);
                continue;
            }
        };

        let ws_url = server_url
            .replace("https://", "wss://")
            .replace("http://", "ws://");
        let full_url = format!("{ws_url}/claw/companion/ws");

        tracing::info!("Connecting to {ws_url}...");

        // Build request with Authorization header
        let request = match Request::builder()
            .uri(&full_url)
            .header("Authorization", format!("Bearer {jwt}"))
            .header("Sec-WebSocket-Key", tungstenite::handshake::client::generate_key())
            .header("Sec-WebSocket-Version", "13")
            .header("Connection", "Upgrade")
            .header("Upgrade", "websocket")
            .header("Host", extract_host(&full_url))
            .body(())
        {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("Failed to build WS request: {e}");
                tokio::time::sleep(std::time::Duration::from_millis(backoff)).await;
                backoff = (backoff * 2).min(MAX_BACKOFF_MS);
                continue;
            }
        };

        match connect_async(request).await {
            Ok((ws_stream, response)) => {
                // Check for auth rejection in upgrade response
                if response.status() == 401 {
                    tracing::warn!("Server returned 401 — clearing JWT and re-pairing");
                    let _ = clear_jwt();
                    continue;
                }

                tracing::info!("Connected to claw server");
                backoff = INITIAL_BACKOFF_MS;

                let (mut write, mut read) = ws_stream.split();

                // Create channel for outbound messages from other modules
                let (tx, mut rx) = mpsc::unbounded_channel::<String>();

                // Store sender in app state for other modules.
                // manage() is safe to call multiple times in Tauri 2.x (returns false if already set).
                // On reconnect the old sender is stale, but screen_lock and other modules
                // will pick up the new sender via the WsSender channel stored here.
                app_handle.manage(WsSenderState(tx.clone()));

                // Send capabilities registration
                let caps = serde_json::json!({
                    "type": "capabilities",
                    "platform": std::env::consts::OS,
                    "version": env!("CARGO_PKG_VERSION"),
                    "actions": [
                        "file_sync", "notification", "screen_lock",
                        "token_sync", "os_control", "browser"
                    ]
                });
                let _ = write
                    .send(tungstenite::Message::Text(caps.to_string()))
                    .await;

                // Spawn writer task for outbound messages
                let write_handle = tokio::spawn(async move {
                    while let Some(msg) = rx.recv().await {
                        if write
                            .send(tungstenite::Message::Text(msg))
                            .await
                            .is_err()
                        {
                            break;
                        }
                    }
                });

                // Process incoming messages
                while let Some(msg) = read.next().await {
                    match msg {
                        Ok(tungstenite::Message::Text(text)) => {
                            handle_server_message(&text, &app_handle, &tx).await;
                        }
                        Ok(tungstenite::Message::Close(frame)) => {
                            // Check if close reason indicates auth failure
                            if let Some(ref f) = frame {
                                if f.code == tungstenite::protocol::frame::coding::CloseCode::Policy
                                {
                                    tracing::warn!("Server closed with policy error — re-pairing");
                                    let _ = clear_jwt();
                                }
                            }
                            tracing::info!("Server closed connection");
                            break;
                        }
                        Err(e) => {
                            tracing::warn!("WebSocket error: {e}");
                            // Check for 401 in error message
                            let err_str = e.to_string();
                            if err_str.contains("401") || err_str.contains("Unauthorized") {
                                tracing::warn!("Auth error detected — clearing JWT");
                                let _ = clear_jwt();
                            }
                            break;
                        }
                        _ => {}
                    }
                }

                write_handle.abort();
            }
            Err(e) => {
                let err_str = e.to_string();
                if err_str.contains("401") || err_str.contains("Unauthorized") {
                    tracing::warn!("Connection rejected with 401 — clearing JWT and re-pairing");
                    let _ = clear_jwt();
                    // Short delay then retry with fresh pairing
                    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                    continue;
                }
                tracing::warn!("Connection failed: {e}");
            }
        }

        // Reconnect with exponential backoff
        tracing::info!("Reconnecting in {backoff}ms...");
        tokio::time::sleep(std::time::Duration::from_millis(backoff)).await;
        backoff = (backoff * 2).min(MAX_BACKOFF_MS);
    }
}

/// Tauri managed state for the WS sender.
pub struct WsSenderState(pub WsSender);

/// Extract host from a URL string for the Host header.
fn extract_host(url: &str) -> String {
    url::Url::parse(url)
        .map(|u| {
            let host = u.host_str().unwrap_or("localhost").to_string();
            match u.port() {
                Some(p) => format!("{host}:{p}"),
                None => host,
            }
        })
        .unwrap_or_else(|_| "localhost".into())
}

async fn handle_server_message(text: &str, app_handle: &tauri::AppHandle, ws_tx: &WsSender) {
    let msg: serde_json::Value = match serde_json::from_str(text) {
        Ok(v) => v,
        Err(_) => return,
    };

    let msg_type = msg["type"].as_str().unwrap_or("");
    let request_id = msg["request_id"].as_str().map(|s| s.to_string());

    match msg_type {
        "file_write" => {
            let path = msg["path"].as_str().unwrap_or("");
            let content = msg["content"].as_str().unwrap_or("");
            crate::file_sync::handle_file_write(path, content, app_handle).await;
        }
        "notification" => {
            let title = msg["title"].as_str().unwrap_or("nClaw");
            let body = msg["body"].as_str().unwrap_or("");
            crate::notifications::show_notification(title, body);
        }
        "screen_lock_query" => {
            let locked = crate::screen_lock::is_screen_locked();
            let resp = serde_json::json!({
                "type": "screen_lock_status",
                "locked": locked,
                "request_id": request_id,
            });
            let _ = ws_tx.send(resp.to_string());
        }
        "os_control" => {
            let result = crate::os_control::handle_os_command(&msg).await;
            let resp = match result {
                Ok(data) => serde_json::json!({
                    "type": "os_control_result",
                    "ok": true,
                    "data": data,
                    "request_id": request_id,
                }),
                Err(e) => serde_json::json!({
                    "type": "os_control_result",
                    "ok": false,
                    "error": e,
                    "request_id": request_id,
                }),
            };
            let _ = ws_tx.send(resp.to_string());
        }
        "browser_open" => {
            let url = msg["url"].as_str().unwrap_or("").to_string();
            let mode = msg["mode"].as_str().unwrap_or("text").to_string();
            let rid = request_id.clone();
            let tx = ws_tx.clone();
            let ah = app_handle.clone();
            tokio::spawn(async move {
                let result = crate::browser::handle_browser_open(&url, &mode, &ah).await;
                let resp = match result {
                    Ok(data) => serde_json::json!({
                        "type": "browser_result",
                        "ok": true,
                        "data": data,
                        "request_id": rid,
                    }),
                    Err(e) => serde_json::json!({
                        "type": "browser_result",
                        "ok": false,
                        "error": e,
                        "request_id": rid,
                    }),
                };
                let _ = tx.send(resp.to_string());
            });
        }
        _ => {
            tracing::debug!("Unknown message type: {msg_type}");
        }
    }
}
