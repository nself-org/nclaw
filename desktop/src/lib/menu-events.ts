// ɳClaw Desktop — menu event bridge (frontend)
import { listen } from "@tauri-apps/api/event";

/**
 * All menu item IDs that emit events to the frontend.
 *
 * macOS-only items (e.g. Preferences) use the same string IDs so the backend
 * can route them consistently across platforms.
 */
export type MenuId =
  | "new-chat"
  | "export"
  | "toggle-sidebar"
  | "toggle-dark-mode"
  | "docs"
  | "report-issue"
  | "about";

/**
 * Subscribes to a native menu event by its ID.
 *
 * Returns an unlisten function — call it to remove the listener.
 *
 * @example
 * const stop = onMenu("new-chat", () => dispatch(startNewChat()));
 * // later:
 * stop();
 */
export function onMenu(id: MenuId, handler: () => void): Promise<() => void> {
  return listen(`menu:${id}`, handler);
}
