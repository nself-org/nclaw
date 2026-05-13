export type ThemeMode = 'light' | 'dark' | 'system';

export interface AccentPreset {
  id: string;
  label: string;
  hex: string;
}

export const ACCENT_PRESETS: AccentPreset[] = [
  { id: 'sky', label: 'Sky (default)', hex: '#0ea5e9' },
  { id: 'violet', label: 'Violet', hex: '#8b5cf6' },
  { id: 'emerald', label: 'Emerald', hex: '#10b981' },
  { id: 'amber', label: 'Amber', hex: '#f59e0b' },
  { id: 'rose', label: 'Rose', hex: '#f43f5e' },
  { id: 'slate', label: 'Slate', hex: '#64748b' },
];

export function isValidHex(hex: string): boolean {
  return /^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(hex);
}

export function applyTheme(mode: ThemeMode, accentHex: string): void {
  const root = document.documentElement;
  let effectiveMode: 'light' | 'dark' = 'dark';
  if (mode === 'system') {
    effectiveMode = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  } else {
    effectiveMode = mode;
  }
  root.classList.toggle('dark', effectiveMode === 'dark');
  root.classList.toggle('light', effectiveMode === 'light');
  root.style.setProperty('--accent', accentHex.startsWith('#') ? accentHex : `#${accentHex}`);
}

export function loadThemeFromStorage(): { mode: ThemeMode; accentHex: string } {
  const mode = (localStorage.getItem('nclaw.theme.mode') as ThemeMode) || 'system';
  const accentHex = localStorage.getItem('nclaw.theme.accent') || '#0ea5e9';
  return { mode, accentHex };
}

export function saveTheme(mode: ThemeMode, accentHex: string): void {
  localStorage.setItem('nclaw.theme.mode', mode);
  localStorage.setItem('nclaw.theme.accent', accentHex);
}
