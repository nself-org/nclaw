// ɳClaw Desktop — window management helpers (frontend)
import { invoke } from "@tauri-apps/api/core";

/**
 * Opens the settings window, or focuses it if already open.
 * Delegates to the `open_settings_cmd` Tauri command.
 */
export async function openSettingsWindow(): Promise<void> {
  await invoke<void>("open_settings_cmd");
}

/**
 * Toggles the debug window: shows it if hidden/absent, hides it if visible.
 * Delegates to the `toggle_debug_cmd` Tauri command.
 * Also triggered by the Cmd+Alt+D / Ctrl+Alt+D global shortcut registered in main.rs.
 */
export async function toggleDebugWindow(): Promise<void> {
  await invoke<void>("toggle_debug_cmd");
}
