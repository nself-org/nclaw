# ɳClaw Desktop — Native Menus

Native menus are built in `desktop/src-tauri/src/menu.rs` using Tauri 2's built-in
`tauri::menu` APIs. No third-party plugin is required.

## Menu Structure

| Submenu | Items |
|---------|-------|
| **ɳClaw** (macOS only) | About, Preferences (⌘,), Services, Hide, Hide Others, Show All, Quit |
| **File** | New Chat (⌘N / Ctrl+N), Export, Close Window — plus Quit on non-macOS |
| **Edit** | Undo, Redo, Cut, Copy, Paste, Select All (all predefined) |
| **View** | Toggle Sidebar (⌘\\ / Ctrl+\\), Toggle Dark Mode |
| **Window** | Minimize, Zoom (macOS only) |
| **Help** | Documentation, Report Issue — plus About on non-macOS |

## Platform Differences

- **macOS** adds an "ɳClaw" app submenu (standard convention). Quit lives there. About lives there. Help only shows Docs + Report Issue.
- **Windows / Linux** omit the app submenu. Quit is the last item in File. About appears at the bottom of Help.
- `PredefinedMenuItem::zoom` is macOS-only and guarded by `#[cfg(target_os = "macos")]`.

## Frontend Integration

Menu events that don't have a Rust-side handler (everything except `settings` and `quit`)
are forwarded to the main window as `menu:<id>` Tauri events.

Subscribe in the frontend using the `onMenu` helper:

```ts
import { onMenu } from "$lib/menu-events";

const stop = onMenu("new-chat", () => startNewChat());
// clean up on component destroy:
stop();
```

Available IDs: `new-chat`, `export`, `toggle-sidebar`, `toggle-dark-mode`, `docs`,
`report-issue`, `about`.
