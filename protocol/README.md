# nclaw/protocol/

Sync schema and IDL for nClaw cross-platform state replication.

## Status

Placeholder (P101 S12.T02). Schema files (proto/openapi/json-schema) land in subsequent S12 tickets.

## Purpose

Per [architecture-decisions.md](../.claude/phases/current/p101-storm/architecture-decisions.md) Decision #2:

- Defines wire format between desktop (Tauri), mobile (Flutter), and server (Hasura).
- Single source of truth for event-log entries, sync envelopes, and conflict-resolution metadata.
- Generates typed clients in TS (via tauri-specta / ts-rs), Dart (via flutter_rust_bridge codegen), and Rust (native, shared with `core/`).

## Layout (planned)

```text
protocol/
├── events/        — event schemas (np_* entity mutations, vault updates, presence)
├── sync/          — sync envelope, ack, conflict resolution
├── plugin/        — MCP-style plugin protocol (server-side, called from local app)
└── README.md
```

Cross-ref: Decision #5 (sync engine), Decision #6 (cross-language bindings), Decision #11 (plugin integration).
