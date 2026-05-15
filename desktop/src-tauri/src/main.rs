// ɳClaw Desktop — Tauri 2 entry point
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod downgrade_guard;
mod menu;
mod tray;
mod windows;

use tauri::{Emitter, Manager, WindowEvent};
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
        // Updater plugin: checks packages.nself.org/desktop/latest-{target}.json
        // using Ed25519 signature verification (key set in tauri.conf.json pubkey field).
        // downgrade_guard ensures version <= current is rejected before install.
        .plugin(tauri_plugin_updater::Builder::new().build())
        // Register autostart plugin. Auto-start is OFF by default — the frontend
        // settings UI can call `invoke('plugin:autostart|enable')` to opt in.
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None, // no extra launch args
        ))
        .invoke_handler(tauri::generate_handler![
            open_settings_cmd,
            toggle_debug_cmd,
            commands::chat::stream_chat,
            commands::local_ai::get_tier,
            commands::local_ai::get_benchmark_history,
            commands::local_ai::list_models,
            commands::local_ai::run_benchmark,
            commands::local_ai::import_custom_gguf,
            commands::local_ai::set_tier_override,
            commands::local_ai::set_allow_t4,
            commands::local_ai::set_re_bench_monthly,
            commands::local_ai::delete_model,
            commands::local_ai::set_model_role,
            commands::local_ai::get_upgrade_config,
            commands::local_ai::upgrade_to_tier,
            commands::local_ai::set_upgrade_prompt_disabled,
            commands::local_ai::defer_upgrade_prompt_30_days,
            commands::palette::palette_search,
            commands::settings::get_setting,
            commands::settings::get_all_settings,
            commands::settings::set_setting,
            commands::settings::test_sync_connection,
            commands::theme::set_window_theme,
            commands::topics::list_topics,
            commands::topics::move_topic,
            commands::topics::search,
            commands::vault::vault_status,
            commands::vault::vault_repair_device,
            commands::vault::vault_revoke_device,
            commands::vault::vault_sync_now,
        ])
        .menu(menu::build_app_menu)
        .on_menu_event(|app, event| {
            let id = event.id().0.as_str();
            match id {
                "settings" => {
                    let _ = windows::open_settings(app);
                }
                "quit" => {
                    app.exit(0);
                }
                other => {
                    // Forward all other menu events to the main window as
                    // "menu:<id>" so the frontend can subscribe via onMenu().
                    let _ = app.emit_to("main", &format!("menu:{}", other), ());
                }
            }
        })
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

            // Build system tray. Linux may not support tray icons — log and continue.
            #[cfg(any(target_os = "macos", target_os = "windows"))]
            tray::build_tray(app)?;

            #[cfg(target_os = "linux")]
            {
                // Tray may be unavailable without libappindicator; attempt and ignore failure.
                eprintln!("[nclaw-desktop] warning: system tray may not be available on this Linux session");
                let _ = tray::build_tray(app);
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
