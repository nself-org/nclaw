# Command Palette

**Keyboard Shortcut:** Cmd-K (macOS) / Ctrl-K (Windows/Linux)

The command palette provides quick access to topics, conversations, and actions from anywhere in ɳClaw Desktop.

## Features

- **Search topics and conversations** — fuzzy search across your memory
- **Quick commands** — New Chat, Settings, Dark Mode, Export, Debug Window
- **Recent conversations** — navigate history without scrolling
- **Keyboard-first** — navigate with ↑↓, activate with Enter, close with Esc

## Keyboard Navigation

| Key | Action |
|-----|--------|
| **Cmd-K** | Open palette |
| **↑↓** | Navigate items |
| **Enter** | Activate selection |
| **Esc** | Close |
| **Tab** | Jump to next group |

## Implementation Status

- **S14.T11:** Basic UI + stub backend (canned topics)
- **S17:** Real sync from Postgres (topics + conversations from claw backend)
- **S18:** Full integration with vault + deep linking to specific conversations

See `.claude/tasks/active.md` for current progress.
