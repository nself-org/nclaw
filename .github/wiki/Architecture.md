# ɳClaw v1.1.1 Architecture Overview

This document summarizes the 12 key architectural decisions that define ɳClaw v1.1.1. Each decision area has its own ADR (Architecture Decision Record) in the `adr/` folder for full context.

## Framework Split

ɳClaw ships as two separate native applications: Tauri 2 for macOS/Linux/Windows desktop, and Flutter for iOS/Android mobile. Each codebase is optimized for its platform while sharing a unified Rust core. The v1.1.0 Flutter desktop implementation is archived for reference but not maintained.

Full ADR: [adr/0001-framework-split.md](adr/0001-framework-split.md)

## Monorepo Layout

The nclaw repository is now a monorepo containing four main directories: `desktop/` (Tauri 2 + React + Vite), `mobile/` (Flutter), `core/` (Rust crate), and `protocol/` (sync schema and IDL). A `legacy-flutter-desktop/` directory preserves the v1.1.0 Flutter desktop implementation as read-only reference.

Full ADR: [adr/0002-repo-structure.md](adr/0002-repo-structure.md)

## Runtime Architecture

The core runtime uses Rust with tokio for async execution and structured tracing throughout. This provides memory safety, high concurrency, and observable production behavior. Desktop and mobile frontends compile the core to platform-native modules via FFI.

Full ADR: [adr/0003-runtime.md](adr/0003-runtime.md)

## Local Database Strategy

Desktop uses pglite (Postgres compiled to WASM), offering schema parity with the server. Mobile uses SQLite with the sqlite-vec extension for vector embeddings. The sync layer handles schema translation where they diverge.

Full ADR: [adr/0004-local-database.md](adr/0004-local-database.md)

## Sync Engine Design

Offline-first synchronization uses a custom event log with last-write-wins (LWW) conflict resolution and Hasura subscriptions. This is single-user multi-device (not collaborative), with a clear upgrade path to CRDT if multi-device conflicts become real.

Full ADR: [adr/0005-sync-engine.md](adr/0005-sync-engine.md)

## Cross-Language Bindings

Desktop uses tauri-specta and ts-rs for type-safe Rust ↔ TypeScript bindings. Mobile uses flutter_rust_bridge. Both approaches eliminate manual FFI boilerplate and ensure frontend/backend types stay synchronized.

Full ADR: [adr/0006-cross-language-bindings.md](adr/0006-cross-language-bindings.md)

## Credential Vault Design

The server holds encrypted credential blobs as the record of truth. Each device stores a per-device keypair in the OS keychain (via keyring-rs on desktop, flutter_secure_storage on mobile). The server encrypts blobs with a user master key and per-device public key envelope, so device loss does not expose credentials.

Full ADR: [adr/0007-credential-vault.md](adr/0007-credential-vault.md)

## Legacy Desktop Handling

The v1.1.0 Flutter desktop implementation is archived as a frozen branch with a README explaining the migration to Tauri 2. No production users require migration support. v1.1.1 ships the archive alongside Tauri 2; v1.2.0 removes it entirely.

Full ADR: [adr/0008-legacy-archive.md](adr/0008-legacy-archive.md)

## Device-Aware Local LLM

At first run, the app benchmarks device hardware and selects an optimal model tier (T0–T4). The tier matrix covers Android 4GB phones through M2 Max workstations. Models are Llama 3.2 and Qwen 2.5 at various quantization levels, cached locally and swapped by user preference. Monthly re-benchmarking ensures tier selection stays accurate.

Full ADR: [adr/0009-device-aware-llm.md](adr/0009-device-aware-llm.md)

## Sync Direction Policy

Local writes land instantly, queue to the server, and fan out to other devices via subscriptions. The server is the record of truth; conflicts are resolved per-entity using LWW with a manual-resolve UI hook for cases where it matters.

Full ADR: [adr/0010-sync-direction.md](adr/0010-sync-direction.md)

## Plugin Integration

The app calls server plugins (calendar, email, browser, news, budget, voice, etc.) over HTTPS using an MCP-style protocol. No local plugin runtime ships in v1.1.1; that's deferred to v1.2.x. Local LLM, sync, and vault are the v1.1.1 foundation.

Full ADR: [adr/0011-plugin-integration.md](adr/0011-plugin-integration.md)

## Versioning Policy

The nclaw monorepo uses a single version number for desktop, mobile, core, and protocol. All components ship together at the same semantic version. This simplifies releases and keeps compatibility clear.

Full ADR: [adr/0012-versioning.md](adr/0012-versioning.md)
