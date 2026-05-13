# System Tray

The ɳClaw desktop app places an icon in the system tray for quick access without keeping the main window open.

## Icon States

| State | Color | Meaning |
|---|---|---|
| **Connected** | Green | Backend reachable, syncing active |
| **Offline** | Gray | Cannot reach the configured nSelf server |
| **Syncing** | Sky blue | Memory sync or initial load in progress |

The initial state on launch is Offline. The icon updates when the WebSocket connection to the backend changes state.

## Tray Menu

- **Open ɳClaw** — shows and focuses the main window
- **New Chat** — emits a `menu:new-chat` event the frontend handles identically to the keyboard shortcut
- **Status: \<state\>** — read-only label; text updates with connection state
- **Settings…** — opens the settings window
- **Quit** — exits the app completely

## Platform Differences

| Platform | Left-click behavior |
|---|---|
| macOS | Opens the context menu (system default) |
| Windows | Toggles main window visibility |
| Linux | Context menu (if `libappindicator` is available); a warning is logged if tray cannot be created, and the app continues normally |

## Auto-Start

The autostart plugin is registered but **disabled by default**. Users opt in from the Settings panel, which calls `invoke('plugin:autostart|enable')`. The LaunchAgent mechanism is used on macOS.

## Developer Notes

Tray icon images are 1x1 placeholder PNGs. Final artwork ships in the S14.T15 build/icons sprint. To swap the icon programmatically call `tray::set_status(&app_handle, TrayState::Connected)`.
