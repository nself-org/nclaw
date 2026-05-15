// ɳClaw Desktop — native application menu

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};

/// Builds the platform-appropriate application menu.
///
/// macOS gets an "App" (ɳClaw) submenu with About / Preferences / Quit plus
/// standard Services / Hide items. Windows and Linux skip the App submenu and
/// instead append Close + Quit to the File submenu.
pub fn build_app_menu(handle: &tauri::AppHandle) -> tauri::Result<Menu<tauri::Wry>> {

    // ── File ──────────────────────────────────────────────────────────────────
    let new_chat = MenuItem::with_id(handle, "new-chat", "New Chat", true, Some("CmdOrCtrl+N"))?;
    let export = MenuItem::with_id(handle, "export", "Export", true, None::<&str>)?;
    let close_window = PredefinedMenuItem::close_window(handle, None)?;

    #[cfg(target_os = "macos")]
    let file_submenu =
        Submenu::with_items(handle, "File", true, &[&new_chat, &export, &close_window])?;

    #[cfg(not(target_os = "macos"))]
    let quit = PredefinedMenuItem::quit(handle, None)?;

    #[cfg(not(target_os = "macos"))]
    let file_submenu = Submenu::with_items(
        handle,
        "File",
        true,
        &[&new_chat, &export, &close_window, &quit],
    )?;

    // ── Edit ──────────────────────────────────────────────────────────────────
    let edit_submenu = Submenu::with_items(
        handle,
        "Edit",
        true,
        &[
            &PredefinedMenuItem::undo(handle, None)?,
            &PredefinedMenuItem::redo(handle, None)?,
            &PredefinedMenuItem::separator(handle)?,
            &PredefinedMenuItem::cut(handle, None)?,
            &PredefinedMenuItem::copy(handle, None)?,
            &PredefinedMenuItem::paste(handle, None)?,
            &PredefinedMenuItem::select_all(handle, None)?,
        ],
    )?;

    // ── View ──────────────────────────────────────────────────────────────────
    let toggle_sidebar = MenuItem::with_id(
        handle,
        "toggle-sidebar",
        "Toggle Sidebar",
        true,
        Some("CmdOrCtrl+\\"),
    )?;
    let toggle_dark_mode = MenuItem::with_id(
        handle,
        "toggle-dark-mode",
        "Toggle Dark Mode",
        true,
        None::<&str>,
    )?;
    let view_submenu =
        Submenu::with_items(handle, "View", true, &[&toggle_sidebar, &toggle_dark_mode])?;

    // ── Window ────────────────────────────────────────────────────────────────
    let minimize = PredefinedMenuItem::minimize(handle, None)?;

    // Tauri 2 removed `PredefinedMenuItem::zoom`; `maximize` is the closest
    // semantic replacement (toggles window zoom/restore state on macOS).
    #[cfg(target_os = "macos")]
    let zoom = PredefinedMenuItem::maximize(handle, None)?;

    #[cfg(target_os = "macos")]
    let window_submenu = Submenu::with_items(handle, "Window", true, &[&minimize, &zoom])?;

    #[cfg(not(target_os = "macos"))]
    let window_submenu = Submenu::with_items(handle, "Window", true, &[&minimize])?;

    // ── Help ──────────────────────────────────────────────────────────────────
    let docs = MenuItem::with_id(handle, "docs", "Documentation", true, None::<&str>)?;
    let report_issue =
        MenuItem::with_id(handle, "report-issue", "Report Issue", true, None::<&str>)?;

    // "About" in Help only on non-macOS; macOS puts it in the App submenu.
    #[cfg(target_os = "macos")]
    let help_submenu = Submenu::with_items(handle, "Help", true, &[&docs, &report_issue])?;

    #[cfg(not(target_os = "macos"))]
    let about_help = MenuItem::with_id(handle, "about", "About ɳClaw", true, None::<&str>)?;

    #[cfg(not(target_os = "macos"))]
    let help_submenu = Submenu::with_items(
        handle,
        "Help",
        true,
        &[
            &docs,
            &report_issue,
            &PredefinedMenuItem::separator(handle)?,
            &about_help,
        ],
    )?;

    // ── macOS "ɳClaw" app submenu ─────────────────────────────────────────────
    #[cfg(target_os = "macos")]
    {
        let about = PredefinedMenuItem::about(handle, None, None)?;
        let preferences = MenuItem::with_id(
            handle,
            "settings",
            "Preferences\u{2026}",
            true,
            Some("Cmd+,"),
        )?;
        let services = PredefinedMenuItem::services(handle, None)?;
        let hide = PredefinedMenuItem::hide(handle, None)?;
        let hide_others = PredefinedMenuItem::hide_others(handle, None)?;
        let show_all = PredefinedMenuItem::show_all(handle, None)?;
        let quit = PredefinedMenuItem::quit(handle, None)?;

        let app_submenu = Submenu::with_items(
            handle,
            "ɳClaw",
            true,
            &[
                &about,
                &PredefinedMenuItem::separator(handle)?,
                &preferences,
                &PredefinedMenuItem::separator(handle)?,
                &services,
                &PredefinedMenuItem::separator(handle)?,
                &hide,
                &hide_others,
                &show_all,
                &PredefinedMenuItem::separator(handle)?,
                &quit,
            ],
        )?;

        return Menu::with_items(
            handle,
            &[
                &app_submenu,
                &file_submenu,
                &edit_submenu,
                &view_submenu,
                &window_submenu,
                &help_submenu,
            ],
        );
    }

    // ── Non-macOS menu ────────────────────────────────────────────────────────
    #[cfg(not(target_os = "macos"))]
    Menu::with_items(
        handle,
        &[
            &file_submenu,
            &edit_submenu,
            &view_submenu,
            &window_submenu,
            &help_submenu,
        ],
    )
}
