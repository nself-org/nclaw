// ɳClaw Desktop — menu event bridge (frontend)
import { listen } from "@tauri-apps/api/event";
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
export function onMenu(id, handler) {
    return listen(`menu:${id}`, handler);
}
