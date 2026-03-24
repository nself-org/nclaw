# nClaw

Open-source client apps for [nClaw](https://claw.nself.org), the AI assistant platform powered by nSelf.

Connects to your own nSelf server running the `nself-claw` pro plugin. You own your data, your models, your infrastructure.

## Structure

```
app/              Flutter client (iOS, Android, macOS, web)
apps/
  ios/            SwiftUI native client for iOS and macOS
  android/        Kotlin + Jetpack Compose native client for Android
  desktop/        Tauri desktop client
desktop/          Swift Package for macOS native integration
libs/
  libnclaw/       Shared Rust FFI library (types, protocol, E2E encryption)
backend/          nSelf backend config for self-hosters
```

## Requirements

- An [nSelf](https://nself.org) server with the `nself-claw` pro plugin installed
- Valid nSelf pro license key

## Quick Start

```bash
# Set up the backend
cd backend
nself plugin install ai mux claw
nself build
nself start
```

Then build and run any client app against your server.

## License

MIT
