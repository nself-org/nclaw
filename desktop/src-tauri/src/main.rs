// ɳClaw Desktop — Tauri 2 entry point
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod windows;

use tauri::{Manager, WindowEvent};
use tauri_plugin_global_shortcut::GlobalShortcutExt;

#[tauri::command]
fn open_settings_cmd(app: tauri::AppHandle) -> Result<(), String> {
    windows::open_settings(&app).map_err(|e| e.to_string())
}

#[tauri::command]
fn toggle_debug_cmd(app: tauri::AppHandle) -> Result<(), String> {
    windows::toggle_debug(&app).map_err(|e| e.to_string())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_window_state::Builder::new().build())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .invoke_handler(tauri::generate_handler![open_settings_cmd, toggle_debug_cmd])
        .on_window_event(|window, event| {
            if window.label() == "main" {
                if let WindowEvent::CloseRequested { api, .. } = event {
                    #[cfg(target_os = "macos")]
                    {
                        api.prevent_close();
                        let _ = window.hide();
                    }
                    #[cfg(not(target_os = "macos"))]
                    {
                        let _ = api; // suppress unused warning on non-macOS
                        window.app_handle().exit(0);
                    }
                }
            }
        })
        .setup(|app| {
            // Register global shortcut: Cmd+Alt+D (macOS) / Ctrl+Alt+D (Linux/Windows)
            #[cfg(target_os = "macos")]
            let shortcut = "Cmd+Alt+D";
            #[cfg(not(target_os = "macos"))]
            let shortcut = "Ctrl+Alt+D";

            let app_handle = app.handle().clone();
            app.global_shortcut().on_shortcut(shortcut, move |_app, _shortcut, _event| {
                let _ = windows::toggle_debug(&app_handle);
            })?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
