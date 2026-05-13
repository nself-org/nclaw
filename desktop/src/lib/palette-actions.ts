// ɳClaw Desktop — Command Palette actions and types

export type PaletteResultKind = 'topic' | 'conversation' | 'setting' | 'command';

export interface PaletteResult {
  kind: PaletteResultKind;
  id: string;
  label: string;
  description?: string;
  icon?: string;
  shortcut?: string;
}

export const STATIC_COMMANDS: PaletteResult[] = [
  {
    kind: 'command',
    id: 'new-chat',
    label: 'New Chat',
    description: 'Start a new conversation',
    shortcut: 'Cmd+N',
  },
  {
    kind: 'command',
    id: 'toggle-dark-mode',
    label: 'Toggle Dark Mode',
    description: 'Switch between light and dark theme',
  },
  {
    kind: 'command',
    id: 'export',
    label: 'Export Conversation',
    description: 'Export current conversation as Markdown',
  },
  {
    kind: 'command',
    id: 'open-settings',
    label: 'Open Settings',
    description: 'Configure ɳClaw',
    shortcut: 'Cmd+,',
  },
  {
    kind: 'command',
    id: 'open-debug',
    label: 'Open Debug Window',
    description: 'Show debug console',
    shortcut: 'Cmd+Alt+D',
  },
];

export async function paletteSearch(query: string): Promise<PaletteResult[]> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<PaletteResult[]>('palette_search', { query });
}
