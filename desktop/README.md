# nclaw/desktop/

Tauri 2 desktop app — React + Vite + Tailwind frontend, Rust glue in `src-tauri/`.

Per [architecture-decisions.md](../.claude/phases/current/p101-storm/architecture-decisions.md) Decision #1, desktop is Tauri 2 (Flutter desktop archived in `../legacy-flutter-desktop/`).

## Layout (current)

```text
desktop/
└── src-tauri/        — Tauri 2 Rust backend (port of v1.1.0 nself-companion menu-bar app)
```

`src-ui/` (React + Vite + Tailwind) lands in S13–S14.

## Build

```bash
cd desktop/src-tauri
cargo tauri dev      # dev
cargo tauri build    # release
```

## Bridge to core/

`src-tauri/Cargo.toml` consumes `../../core/` as a workspace dependency once `core/` exposes the shared types (S13). Today it embeds its own types pending consolidation.

## What changed

- v1.1.0: this slot was Swift menu-bar daemon (now at `../legacy-flutter-desktop/swift-daemon/`).
- v1.1.1: replaced by Tauri 2 (P101 S12.T02 monorepo restructure). Tauri scaffold moved from `apps/desktop/src-tauri/` to `desktop/src-tauri/`.
