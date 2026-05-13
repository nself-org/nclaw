// ɳClaw Desktop — system tray icon + menu
//
// Three icon states: Connected (green), Offline (gray), Syncing (sky-blue).
// Placeholder 1x1 PNGs are shipped here; final artwork lands in S14.T15
// (build/icons sprint). Paths are resolved at runtime via `app.path()`.
//
// Platform behaviour:
//   macOS   — left-click opens the context menu (Tauri default)
//   Windows — left-click toggles main window visibility
//   Linux   — tray may be unavailable; logs a warning and continues without panic

use tauri::{
    image::Image,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};

/// The three visual states the tray icon can display.
#[derive(Debug, Clone, Copy)]
pub enum TrayState {
    Connected,
    Offline,
    Syncing,
}

impl TrayState {
    fn icon_filename(self) -> &'static str {
        match self {
            TrayState::Connected => "tray-connected.png",
            TrayState::Offline => "tray-offline.png",
            TrayState::Syncing => "tray-syncing.png",
        }
    }
}

/// Builds and registers the system tray icon with its context menu.
///
/// Call once from the `setup` hook in `main.rs`.
pub fn build_tray(app: &tauri::App) -> tauri::Result<()> {
    let handle = app.handle();

    // Resolve icon path and load initial (Offline) icon.
    let icon = load_icon(handle, TrayState::Offline)?;

    // ── Tray menu ─────────────────────────────────────────────────────────────
    let open_item = MenuItem::with_id(handle, "tray-open", "Open ɳClaw", true, None::<&str>)?;
    let new_chat = MenuItem::with_id(handle, "tray-new-chat", "New Chat", true, None::<&str>)?;
    let status = MenuItem::with_id(
        handle,
        "tray-status",
        "Status: Offline",
        false,
        None::<&str>,
    )?;
    let sep1 = PredefinedMenuItem::separator(handle)?;
    let settings = MenuItem::with_id(
        handle,
        "tray-settings",
        "Settings\u{2026}",
        true,
        None::<&str>,
    )?;
    let sep2 = PredefinedMenuItem::separator(handle)?;
    let quit = MenuItem::with_id(handle, "tray-quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(
        handle,
        &[
            &open_item, &new_chat, &status, &sep1, &settings, &sep2, &quit,
        ],
    )?;

    // ── Build the tray icon ───────────────────────────────────────────────────
    TrayIconBuilder::with_id("nclaw-tray")
        .icon(icon)
        .menu(&menu)
        .show_menu_on_left_click(true) // macOS default: left-click shows menu
        .on_menu_event({
            let handle = handle.clone();
            move |app, event| {
                let id = event.id().0.as_str();
                match id {
                    "tray-open" => {
                        focus_main(app);
                    }
                    "tray-new-chat" => {
                        let _ = app.emit_to("main", "menu:new-chat", ());
                    }
                    "tray-settings" => {
                        let _ = crate::windows::open_settings(&handle);
                    }
                    "tray-quit" => {
                        app.exit(0);
                    }
                    _ => {}
                }
            }
        })
        .on_tray_icon_event(|tray, event| {
            // Windows: left-click toggles main window (macOS uses menu-on-click).
            #[cfg(target_os = "windows")]
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(win) = app.get_webview_window("main") {
                    if win.is_visible().unwrap_or(false) {
                        let _ = win.hide();
                    } else {
                        let _ = win.show();
                        let _ = win.set_focus();
                    }
                }
            }
            // Suppress unused warnings on non-Windows.
            let _ = (tray, event);
        })
        .build(handle)?;

    Ok(())
}

/// Swaps the tray icon to reflect the current connection state.
///
/// Call this whenever the backend connection state changes, e.g.:
/// ```rust
/// tray::set_status(&app_handle, TrayState::Connected);
/// ```
pub fn set_status(app: &AppHandle, state: TrayState) {
    if let Some(tray) = app.tray_by_id("nclaw-tray") {
        if let Ok(icon) = load_icon(app, state) {
            let _ = tray.set_icon(Some(icon));
        }
    }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

fn load_icon(app: &AppHandle, state: TrayState) -> tauri::Result<Image<'static>> {
    // Resolve to the bundled resources directory at runtime.
    let resource_path = app
        .path()
        .resource_dir()?
        .join("icons")
        .join(state.icon_filename());

    Image::from_path(resource_path).map_err(tauri::Error::from)
}

fn focus_main(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.set_focus();
    }
}
