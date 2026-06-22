// ɳClaw Desktop — Keyboard shortcuts registry
// Central definition of all keyboard shortcuts, with custom override support via localStorage

/** A single keyboard shortcut binding with per-platform key strings and optional user override. */
export interface ShortcutDef {
  id: string;
  label: string;
  section: "Chat" | "Navigation" | "Window" | "Editing";
  default: { mac: string; other: string };
  current?: { mac: string; other: string };
}

/** Factory defaults for all ɳClaw keyboard shortcuts. User overrides are layered on top via localStorage. */
export const DEFAULT_SHORTCUTS: ShortcutDef[] = [
  { id: "new-chat", label: "New Chat", section: "Chat", default: { mac: "⌘N", other: "Ctrl+N" } },
  { id: "send", label: "Send Message", section: "Chat", default: { mac: "Enter", other: "Enter" } },
  { id: "newline", label: "Insert Newline", section: "Chat", default: { mac: "Shift+Enter", other: "Shift+Enter" } },
  { id: "cancel-stream", label: "Cancel Stream", section: "Chat", default: { mac: "Esc", other: "Esc" } },
  { id: "palette", label: "Open Command Palette", section: "Navigation", default: { mac: "⌘K", other: "Ctrl+K" } },
  { id: "palette-commands", label: "Open Commands Group", section: "Navigation", default: { mac: "⌘⇧P", other: "Ctrl+Shift+P" } },
  { id: "toggle-sidebar", label: "Toggle Sidebar", section: "Navigation", default: { mac: "⌘\\", other: "Ctrl+\\" } },
  { id: "toggle-dark-mode", label: "Toggle Dark Mode", section: "Window", default: { mac: "⌘⇧D", other: "Ctrl+Shift+D" } },
  { id: "open-settings", label: "Open Settings", section: "Window", default: { mac: "⌘,", other: "Ctrl+," } },
  { id: "open-debug", label: "Open Debug Window", section: "Window", default: { mac: "⌘⌥D", other: "Ctrl+Alt+D" } },
  { id: "minimize", label: "Minimize Window", section: "Window", default: { mac: "⌘M", other: "Ctrl+M" } },
  { id: "shortcuts-modal", label: "Show All Shortcuts", section: "Window", default: { mac: "?", other: "?" } },
  { id: "undo", label: "Undo", section: "Editing", default: { mac: "⌘Z", other: "Ctrl+Z" } },
  { id: "redo", label: "Redo", section: "Editing", default: { mac: "⌘⇧Z", other: "Ctrl+Shift+Z" } },
];

/** Return all shortcuts with user overrides from localStorage merged into each entry's `current` field. */
export function getShortcuts(): ShortcutDef[] {
  try {
    const stored = localStorage.getItem("nclaw.shortcuts.custom");
    if (!stored) return DEFAULT_SHORTCUTS;
    const customMap = JSON.parse(stored) as Record<string, { mac: string; other: string }>;
    return DEFAULT_SHORTCUTS.map((d) =>
      customMap[d.id] ? { ...d, current: customMap[d.id] } : d
    );
  } catch {
    return DEFAULT_SHORTCUTS;
  }
}

/** Persist a custom key binding for `id` to localStorage. */
export function setShortcut(id: string, value: { mac: string; other: string }): void {
  try {
    const stored = localStorage.getItem("nclaw.shortcuts.custom");
    const map: Record<string, { mac: string; other: string }> = stored ? JSON.parse(stored) : {};
    map[id] = value;
    localStorage.setItem("nclaw.shortcuts.custom", JSON.stringify(map));
  } catch (err) {
    console.error("Failed to save shortcut:", err);
  }
}

/** Remove all custom shortcut overrides, reverting every binding to its default. */
export function resetShortcuts(): void {
  try {
    localStorage.removeItem("nclaw.shortcuts.custom");
  } catch (err) {
    console.error("Failed to reset shortcuts:", err);
  }
}

/** Remove the custom override for a single shortcut `id`, reverting it to its default. */
export function resetShortcut(id: string): void {
  try {
    const stored = localStorage.getItem("nclaw.shortcuts.custom");
    if (!stored) return;
    const map = JSON.parse(stored) as Record<string, { mac: string; other: string }>;
    delete map[id];
    if (Object.keys(map).length === 0) {
      localStorage.removeItem("nclaw.shortcuts.custom");
    } else {
      localStorage.setItem("nclaw.shortcuts.custom", JSON.stringify(map));
    }
  } catch (err) {
    console.error("Failed to reset shortcut:", err);
  }
}
