# Changelog

All notable changes to nClaw are documented here.

## [1.1.1] — 2026-05-13

### Architecture

- **Desktop platform swap:** Flutter desktop → Tauri 2 + React + Vite for better native performance and smaller binary footprint
- Mobile remains on Flutter (iOS, Android)
- See [migration guide](.github/wiki/migration/v1.1.0-to-v1.1.1.md) for details

## [1.0.0] — 2026-03-29

Initial public release of nClaw — open-source AI assistant client for iOS, Android, macOS, and web, powered by a self-hosted nSelf backend.

### Flutter app (`app/`)

- **AI chat** — Multi-turn conversations with persistent memory and context window management
- **Memory and context** — Cross-session memory, context injection, and personal knowledge base
- **Tool calls** — AI executes tools: web search, file read/write, code execution, shell commands
- **Personas** — Custom AI personas with defined behavior, tone, and knowledge scope
- **Proactive intelligence** — Background agent monitoring, event-triggered actions, scheduled tasks
- **Voice** — Speech-to-text input and text-to-speech output via nself-voice plugin
- **Browser automation** — AI-driven browser control via nself-browser plugin (Chrome DevTools Protocol)
- **Multi-modal input** — Images, files, and documents accepted as conversation inputs
- **E2E encryption** — All messages encrypted end-to-end using libnclaw (X25519 + XChaCha20-Poly1305)
- Cross-platform build targets: iOS, Android, macOS, web

### SwiftUI native client (`apps/ios/`)

- Native iOS and macOS client
- Consumes libnclaw FFI bindings for protocol and encryption
- No duplicated type definitions — all types sourced from libnclaw

### Kotlin native client (`apps/android/`)

- Native Android client using Jetpack Compose
- Consumes libnclaw FFI bindings

### Tauri desktop companion (`apps/desktop/`)

- Desktop companion app via Tauri
- Connects to user-configured nSelf backend

### libnclaw (`libs/libnclaw/`)

- Rust FFI library: single source of truth for types, protocol definitions, and E2E encryption
- X25519 key exchange + XChaCha20-Poly1305 message encryption
- FFI bindings generated for Swift, Kotlin, and TypeScript consumers

### Backend config (`backend/`)

- nSelf CLI backend configuration for self-hosters
- Required Pro plugins: `ai`, `claw`, `mux`, `voice`, `browser`
- Pro tier license required (`nself_pro_` key, $1.99/mo or $19.99/yr)
