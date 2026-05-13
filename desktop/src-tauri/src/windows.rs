// ɳClaw Desktop — window management helpers

use tauri::{AppHandle, Manager, WebviewWindowBuilder};

/// Opens the settings window, or focuses it if already open.
pub fn open_settings(app: &AppHandle) -> tauri::Result<()> {
    if let Some(win) = app.get_webview_window("settings") {
        win.show()?;
        win.set_focus()?;
    } else {
        let config = app
            .config()
            .app
            .windows
            .iter()
            .find(|w| w.label == "settings")
            .cloned()
            .expect("settings window config missing from tauri.conf.json");
        WebviewWindowBuilder::from_config(app, &config)?.build()?;
    }
    Ok(())
}

/// Toggles the debug window: shows it if hidden/absent, hides it if visible.
pub fn toggle_debug(app: &AppHandle) -> tauri::Result<()> {
    if let Some(win) = app.get_webview_window("debug") {
        if win.is_visible()? {
            win.hide()?;
        } else {
            win.show()?;
            win.set_focus()?;
        }
    } else {
        let config = app
            .config()
            .app
            .windows
            .iter()
            .find(|w| w.label == "debug")
            .cloned()
            .expect("debug window config missing from tauri.conf.json");
        WebviewWindowBuilder::from_config(app, &config)?.build()?;
    }
    Ok(())
}
