# nClaw

Open-source AI assistant client for iOS, Android, macOS, and web — powered by your own nSelf backend.

Connect to your own self-hosted nSelf server with Pro plugins. You own your data, your models, your infrastructure.

## Architecture

```
Flutter app (app/)
  |
  +-- libnclaw FFI (libs/libnclaw/, Rust)
  |     Types, protocol definitions, E2E encryption (X25519 + XChaCha20-Poly1305)
  |
  +-- nSelf backend (backend/)
        PostgreSQL + Hasura GraphQL + Auth + nSelf Pro plugins
        Required: ai, claw, mux, voice, browser

Native clients:
  apps/ios/      SwiftUI — iOS and macOS
  apps/android/  Kotlin + Jetpack Compose
  apps/desktop/  Tauri desktop companion
```

libnclaw is the single source of truth for types and protocol. All clients consume its FFI bindings — do not duplicate type definitions in client code.

## Requirements

- **nSelf CLI** v1.0+ with a valid Pro license key (`nself_pro_` prefix)
- **Pro plugins** installed: `ai`, `claw`, `mux`, `voice`, `browser`
- **Flutter** 3.x (for `app/` and cross-platform builds)
- **Rust** stable toolchain (for `libs/libnclaw/`)
- **Docker** (for the nSelf backend)
- **Xcode** (iOS/macOS builds) or **Android Studio** (Android builds)

Pro plugins require a Pro tier license ($1.99/mo or $19.99/yr). See [nself.org/pricing](https://nself.org/pricing).

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

- **AI chat** — Multi-turn conversations with memory and context window management
- **Memory and context** — Persistent memory across sessions, context injection, knowledge base
- **Tool calls** — AI executes tools: web search, file read/write, code execution, shell commands
- **Personas** — Custom AI personas with defined behavior, tone, and knowledge scope
- **Proactive intelligence** — Background agent monitoring, event-triggered actions, scheduled tasks
- **Voice** — Speech-to-text input and text-to-speech output via the nself-voice plugin
- **Browser automation** — AI-driven browser control via the nself-browser plugin (CDP)
- **Multi-modal input** — Images, files, and documents as conversation inputs
- **E2E encryption** — All messages encrypted end-to-end via libnclaw (X25519 + XChaCha20-Poly1305)

## Repo Structure

```
app/              Flutter client (iOS, Android, macOS, web)
apps/
  ios/            SwiftUI native client (iOS + macOS)
  android/        Kotlin + Jetpack Compose native client
  desktop/        Tauri desktop companion
libs/
  libnclaw/       Shared Rust FFI library (types, protocol, E2E encryption)
backend/          nSelf backend config for self-hosters
```

## Backend Setup

See [backend/README.md](backend/README.md) for the full self-hosting guide, including environment variable reference, plugin setup, and troubleshooting.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup, code style, and PR guidelines. The [wiki](https://github.com/nself-org/claw/wiki) has detailed architecture and feature documentation.

## License

MIT — free for personal and commercial use. The nSelf Pro plugins required by the backend are separately licensed; see [nself.org/pricing](https://nself.org/pricing).
