# legacy-flutter-desktop/

Frozen v1.1.0 desktop artifacts. Kept for migration reference only.

## Status

Archived as of v1.1.1 (P101 S12.T02 — monorepo restructure 2026-05-13).
**No production users on v1.1.0 desktop.** No migration burden.

## Contents

- `swift-daemon/` — macOS menu-bar Swift daemon. Originally shipped as the local file/clipboard/screenshot bridge between server and machine. Superseded by Tauri 2 desktop (`../desktop/`) which embeds these capabilities natively via tauri plugins.

## Removal schedule

Per [architecture-decisions.md](../.claude/phases/current/p101-storm/architecture-decisions.md) Decision #8:

- **v1.1.1** — archived here, no longer built.
- **v1.2.0** — directory removed entirely.

## Why archived (not deleted now)

Source-level reference during the Tauri 2 port. Once feature parity is confirmed in `desktop/` (S13–S15), this entire directory deletes in v1.2.0.

## Do NOT modify

This directory is frozen. New desktop work belongs in `../desktop/`.
