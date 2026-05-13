//! nSelf Desktop Companion -- system tray app that bridges nClaw server to local machine.
//!
//! Features:
//! - WebSocket connection to claw server (persistent, JWT-authenticated, auto-reconnect)
//! - File sync: server pushes inbox messages to local .claude/inbox/ directories
//! - Token sync: watches gog CLI OAuth token refreshes and syncs to server
//! - System notifications: native macOS/Linux notifications from server
//! - Screen lock detection: reports lock status for quiet-mode decisions
//! - Browser automation: opens URLs in hidden WebView, extracts text/screenshots
//! - OS control: keyboard/mouse simulation with explicit allowlist
//! - Sandboxed file proxy: server file requests require user approval

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod browser;
mod config;
mod file_sync;
mod fs_proxy;
mod notifications;
mod os_control;
mod screen_lock;
mod token_sync;
mod ws_client;

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter("nself_companion=info")
        .init();

    tauri::Builder::default()
        .setup(|app| {
            let config = config::load_config();

            // Create system tray
            let _tray = tauri::tray::TrayIconBuilder::new()
                .tooltip("nSelf Companion")
                .menu_on_left_click(true)
                .build(app)?;

            let app_handle = app.handle().clone();
            let server_url = config.server_url.clone();

            // Start WebSocket connection to claw server (handles its own JWT auth)
            let ws_handle = app_handle.clone();
            let ws_server = server_url.clone();
            tokio::spawn(async move {
                ws_client::run_ws_client(&ws_server, ws_handle).await;
            });

            // Start token sync watcher if enabled
            if config.auto_sync_tokens {
                let token_server = server_url.clone();
                tokio::spawn(async move {
                    token_sync::watch_token_refreshes(&token_server).await;
                });
            }

            // Start screen lock detector (macOS)
            #[cfg(target_os = "macos")]
            {
                let lock_handle = app_handle.clone();
                tokio::spawn(async move {
                    screen_lock::watch_screen_lock(lock_handle).await;
                });
            }

            tracing::info!("nSelf Companion started");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
