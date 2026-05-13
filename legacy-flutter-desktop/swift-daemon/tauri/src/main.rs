mod pairing;
mod watcher;

use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};

#[tauri::command]
fn pair_device(server_url: String, pair_code: String) -> Result<String, String> {
    let rt = tokio::runtime::Handle::current();
    rt.block_on(async {
        pairing::start_pairing(&server_url, &pair_code)
            .await
            .map(|token| format!("Paired successfully. Token length: {}", token.len()))
            .map_err(|e| e.to_string())
    })
}

#[tauri::command]
fn get_status() -> Result<serde_json::Value, String> {
    let server_url =
        std::env::var("NCLAW_SERVER_URL").unwrap_or_else(|_| "not configured".to_string());
    let has_token = std::env::var("NCLAW_AUTH_TOKEN").is_ok();
    let watch_dir =
        std::env::var("NCLAW_WATCH_DIR").unwrap_or_else(|_| "not configured".to_string());

    Ok(serde_json::json!({
        "server_url": server_url,
        "authenticated": has_token,
        "watch_directory": watch_dir,
        "version": env!("CARGO_PKG_VERSION")
    }))
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let pair = MenuItem::with_id(app, "pair", "Pair Device", true, None::<&str>)?;
            let status = MenuItem::with_id(app, "status", "Status", true, None::<&str>)?;
            let separator = PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&pair, &status, &separator, &quit])?;

            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("ɳClaw Companion")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    "pair" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                            let _ = window.eval("window.showPairDialog()");
                        }
                    }
                    "status" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Start file watcher if a watch directory is configured
            if let Ok(watch_dir) = std::env::var("NCLAW_WATCH_DIR") {
                let server_url = std::env::var("NCLAW_SERVER_URL").ok();
                let auth_token = std::env::var("NCLAW_AUTH_TOKEN").ok();

                if let (Some(url), Some(token)) = (server_url, auth_token) {
                    let mut file_watcher = watcher::FileWatcher::new(url, token);
                    if let Err(e) = file_watcher.watch(&watch_dir) {
                        eprintln!("Failed to start file watcher: {}", e);
                    }
                    // Keep the watcher alive for the app lifetime
                    app.manage(file_watcher);
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![pair_device, get_status])
        .run(tauri::generate_context!())
        .expect("error while running ɳClaw Companion");
}
