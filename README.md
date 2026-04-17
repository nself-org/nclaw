# ɳClaw

[![Version](https://img.shields.io/badge/version-1.1.1-blue.svg)](https://github.com/nself-org/claw/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![coverage](https://codecov.io/gh/nself-org/claw/branch/main/graph/badge.svg)](https://codecov.io/gh/nself-org/claw)
<!-- VERSION_BADGE -->

Open-source AI assistant client for iOS, Android, macOS, and web. Powered by your own ɳSelf backend.

Connect to your own self-hosted ɳSelf server with Pro plugins. You own your data, your models, your infrastructure.

## Architecture

```
Flutter app (app/)
  |
  +-- libnclaw FFI (libs/libnclaw/, Rust)
  |     Types, protocol definitions, E2E encryption (X25519 + XChaCha20-Poly1305)
  |
  +-- ɳSelf backend (backend/)
        PostgreSQL + Hasura GraphQL + Auth + ɳSelf Pro plugins
        Required: ai, claw, mux, voice, browser

Native clients:
  apps/ios/      SwiftUI — iOS and macOS
  apps/android/  Kotlin + Jetpack Compose
  apps/desktop/  Tauri desktop companion
```

libnclaw is the single source of truth for types and protocol. All clients consume its FFI bindings. Do not duplicate type definitions in client code.

## Requirements

- **ɳSelf CLI** v1.0+ with a valid Pro license key (`nself_pro_` prefix)
- **Pro plugins** installed: `ai`, `claw`, `mux`, `voice`, `browser`
- **Flutter** 3.x (for `app/` and cross-platform builds)
- **Rust** stable toolchain (for `libs/libnclaw/`)
- **Docker** (for the ɳSelf backend)
- **Xcode** (iOS/macOS builds) or **Android Studio** (Android builds)

Pro plugins require a Pro tier license ($1.99/mo or $19.99/yr). See [nself.org/pricing](https://nself.org/pricing) for details.

## Quick Start

### 1. Set up the backend

```bash
cd backend
nself init
nself license set nself_pro_YOURKEY
nself plugin install ai claw mux voice browser
nself build
nself start
```

See [backend/README.md](backend/README.md) for the full self-hosting guide.

### 2. Build libnclaw

```bash
cd libs/libnclaw
cargo build --release
```

### 3. Run the Flutter app

```bash
cd app
flutter pub get
```

**iOS:**
```bash
flutter run -d ios
```

**Android:**
```bash
flutter run -d android
```

**macOS:**
```bash
flutter run -d macos
```

**Web:**
```bash
flutter run -d chrome
```

Point the app at your backend URL when prompted (e.g., `http://localhost:4000`).

### Native clients

**iOS/macOS (SwiftUI):**
```bash
open apps/ios/nClaw.xcodeproj
# Build and run from Xcode
```

**Android (Kotlin):**
```bash
open apps/android/ in Android Studio
# Build and run from Android Studio
```

## Features

- **AI chat**: Multi-turn conversations with memory and context window management
- **Memory and context**: Persistent memory across sessions, context injection, knowledge base
- **Tool calls**: AI executes tools: web search, file read/write, code execution, shell commands
- **Personas**: Custom AI personas with defined behavior, tone, and knowledge scope
- **Proactive intelligence**: Background agent monitoring, event-triggered actions, scheduled tasks
- **Voice**: Speech-to-text input and text-to-speech output via the nself-voice plugin
- **Browser automation**: AI-driven browser control via the nself-browser plugin (CDP)
- **Multi-modal input**: Images, files, and documents as conversation inputs
- **E2E encryption**: All messages encrypted end-to-end via libnclaw (X25519 + XChaCha20-Poly1305)

## Repo Structure

```
app/              Flutter client (iOS, Android, macOS, web)
apps/
  ios/            SwiftUI native client (iOS + macOS)
  android/        Kotlin + Jetpack Compose native client
  desktop/        Tauri desktop companion
libs/
  libnclaw/       Shared Rust FFI library (types, protocol, E2E encryption)
backend/          ɳSelf backend config for self-hosters
```

## Build Instructions

ɳClaw ships from one Flutter codebase to five platforms, plus a Tauri desktop app and a macOS menu-bar daemon. The wiki has a per-platform build guide for each:

- [iOS Build Guide](https://github.com/nself-org/claw/wiki/iOS-Build-Guide): Xcode 15+, signing, TestFlight, App Store
- [Android Build Guide](https://github.com/nself-org/claw/wiki/Android-Build-Guide): Android Studio Hedgehog+, NDK, FCM, Play Console
- [macOS Build Guide](https://github.com/nself-org/claw/wiki/macOS-Build-Guide): universal binary, notarization, DMG, Sparkle
- [Web Build Guide](https://github.com/nself-org/claw/wiki/Web-Build-Guide): Flutter web, CanvasKit vs HTML, WASM / REST fallback for FFI
- [Desktop Build Guide](https://github.com/nself-org/claw/wiki/Desktop-Build-Guide): Tauri (Linux deb / rpm / AppImage; Windows MSIX / installer)
- [libnclaw Dev Guide](https://github.com/nself-org/claw/wiki/libnclaw-Dev-Guide): Rust FFI library workflow

For the fastest macOS dev loop:

```bash
cd app && flutter pub get && flutter run -d macos
```

## Plugin Requirements

ɳClaw is a consumer of pro plugins. The backend setup installs them via `nself plugin install`.

| Required | Tier | Purpose |
|----------|------|---------|
| `ai` | Pro | LLM gateway |
| `claw` | Pro | AI assistant core |
| `mux` | Pro | Email pipeline, topic detection |

| Optional (ɳClaw Bundle) | Tier | Purpose |
|-------------------------|------|---------|
| `claw-web` | Pro | Web client surface |
| `voice` | Pro | Speech-to-text + text-to-speech |
| `browser` | Pro | Browser automation (CDP) |
| `google` | Pro | Gmail / Calendar / Drive |
| `notify` | Pro | Push notifications (FCM, APNs) |
| `cron` | Pro | Scheduled jobs |
| `claw-budget` | Pro | Budget / spending intelligence (per F06) |
| `claw-news` | Pro | News digest and briefing (per F06) |

Bundle pricing: the ɳClaw Bundle is $0.99/mo. ɳSelf+ ($49.99/yr) covers every bundle plus every nSelf app. See the [ɳClaw bundle](https://nself.org/pricing) for details. Bundle membership is canonical in `.claude/docs/sport/F06-BUNDLE-INVENTORY.md` (internal reference).

## Backend Setup

See [backend/README.md](backend/README.md) for the full self-hosting guide, including environment variable reference, plugin setup, and troubleshooting. Wiki: [Getting Started](https://github.com/nself-org/claw/wiki/Getting-Started).

## Documentation

The [wiki](https://github.com/nself-org/claw/wiki) is the primary documentation surface. Key pages:

- [Architecture Deep Dive](https://github.com/nself-org/claw/wiki/Architecture-Deep-Dive): layers, data flow, plugin map, security
- [AI Chat](https://github.com/nself-org/claw/wiki/AI-Chat): chat surface, streaming, attachments
- [Memory](https://github.com/nself-org/claw/wiki/Memory): auto-topics, knowledge graph, search
- [Personas](https://github.com/nself-org/claw/wiki/Personas): multi-persona setup
- [Tool Calls](https://github.com/nself-org/claw/wiki/Tool-Calls): function calling, audit trail
- [E2E Encryption](https://github.com/nself-org/claw/wiki/E2E-Encryption): threat model, key management
- [Troubleshooting](https://github.com/nself-org/claw/wiki/Troubleshooting): common errors

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup, code style, and PR guidelines. The [wiki](https://github.com/nself-org/claw/wiki) has detailed architecture and feature documentation.

## License

MIT, free for personal and commercial use. The ɳSelf Pro plugins required by the backend are separately licensed; see [nself.org/pricing](https://nself.org/pricing).
