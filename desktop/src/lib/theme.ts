/** Theme mode: light, dark, or follow the OS setting. */
export type ThemeMode = "light" | "dark" | "system";

/** A named accent colour preset available in the Theme settings panel. */
export interface AccentPreset {
  id: string;
  label: string;
  hex: string;
}

/** Built-in accent colour presets. Sky is the default. */
export const ACCENT_PRESETS: AccentPreset[] = [
  { id: "sky", label: "Sky (default)", hex: "#0ea5e9" },
  { id: "violet", label: "Violet", hex: "#8b5cf6" },
  { id: "emerald", label: "Emerald", hex: "#10b981" },
  { id: "amber", label: "Amber", hex: "#f59e0b" },
  { id: "rose", label: "Rose", hex: "#f43f5e" },
  { id: "slate", label: "Slate", hex: "#64748b" },
];

/** Returns true if `hex` is a valid 6- or 8-digit hex colour (with or without leading #). */
export function isValidHex(hex: string): boolean {
  return /^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(hex);
}

/**
 * Apply `mode` and `accentHex` to the root element.
 *
 * Writes `dark`/`light` class and `--accent` CSS variable to `<html>`.
 * `system` mode resolves via `window.matchMedia`.
 */
export function applyTheme(mode: ThemeMode, accentHex: string): void {
  const root = document.documentElement;
  let effectiveMode: "light" | "dark" = "dark";
  if (mode === "system") {
    effectiveMode = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  } else {
    effectiveMode = mode;
  }
  root.classList.toggle("dark", effectiveMode === "dark");
  root.classList.toggle("light", effectiveMode === "light");
  root.style.setProperty("--accent", accentHex.startsWith("#") ? accentHex : `#${accentHex}`);
}

/** Read persisted theme mode and accent hex from localStorage, returning defaults if unset. */
export function loadThemeFromStorage(): { mode: ThemeMode; accentHex: string } {
  const mode = (localStorage.getItem("nclaw.theme.mode") as ThemeMode) || "system";
  const accentHex = localStorage.getItem("nclaw.theme.accent") || "#0ea5e9";
  return { mode, accentHex };
}

/** Persist `mode` and `accentHex` to localStorage for the next session. */
export function saveTheme(mode: ThemeMode, accentHex: string): void {
  localStorage.setItem("nclaw.theme.mode", mode);
  localStorage.setItem("nclaw.theme.accent", accentHex);
}
