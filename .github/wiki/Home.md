# ɳClaw

> Open-source AI assistant client for iOS, Android, macOS, Web, and desktop. Connects to your own self-hosted ɳSelf backend.

## Quick Start

```bash
brew install nself-org/nself/nself
cd backend && nself license set nself_pro_YOURKEY && nself plugin install ai claw mux && nself build && nself start
cd ../app && flutter run
```

ɳClaw launches and prompts for your backend URL. Enter it and sign in.

## Contents

- [Getting Started](#getting-started)
- [Build Guides](#build-guides)
- [Features](#features)
- [Architecture](#architecture)
- [Plugins](#plugins)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Resources](#resources)

## Getting Started

- [[Getting-Started]] — prerequisites, backend setup, first run
- [[Plugin-Requirements]] — required vs optional pro plugins
- [[Architecture]] — component overview (original; see Architecture-Deep-Dive for full flow)

## Build Guides

ɳClaw ships from one Flutter codebase to five platforms, plus a Tauri desktop app and a macOS menu-bar daemon.

- [[iOS-Build-Guide]] — Xcode 15+, signing, TestFlight, App Store
- [[Android-Build-Guide]] — Android Studio Hedgehog+, NDK, FCM, Play Console
- [[macOS-Build-Guide]] — universal binary, notarization, DMG, Sparkle
- [[Web-Build-Guide]] — Flutter web, CanvasKit vs HTML, WASM / REST fallback for FFI
- [[Desktop-Build-Guide]] — Tauri (Linux deb / rpm / AppImage; Windows MSIX / installer)
- [[libnclaw-Dev-Guide]] — Rust FFI library workflow

## Features

- [[AI-Chat]] — multi-turn streaming chat with markdown, attachments, regenerate, branch
- [[Memory]] — infinite self-organizing memory; auto-topics; knowledge graph
- [[Personas]] — multiple AI identities, persona-scoped memory and tools
- [[Tool-Calls]] — function calling: web, browser, files, shell, voice, push, cron
- [[E2E-Encryption]] — X25519 + XChaCha20-Poly1305, per-device keys
- [[Features]] — full feature index

## Architecture

- [[Architecture-Deep-Dive]] — public deep-dive: layers, data flow, plugin map, security
- [[Architecture]] — original component overview

## Plugins

ɳClaw is a consumer of pro plugins. Plugin source lives in `plugins-pro/` (separate repo, license-gated).

| Required | Tier | Purpose |
|----------|------|---------|
| `ai` | Pro (max) | LLM gateway |
| `claw` | Pro (max) | AI assistant core |
| `mux` | Pro | Email pipeline, topic detection |

| Optional (ɳClaw Bundle) | Tier | Purpose |
|-------------------------|------|---------|
| `claw-web` | Pro (max) | Web client surface |
| `voice` | Pro (max) | Speech-to-text + text-to-speech |
| `browser` | Pro (max) | Browser automation (CDP) |
| `google` | Pro | Gmail / Calendar / Drive |
| `notify` | Pro | Push notifications (FCM, APNs) |
| `cron` | Pro | Scheduled jobs |
| `claw-budget` | Pro | Budget / spending intelligence (per F06) |
| `claw-news` | Pro | News digest / briefings (per F06) |

See `~/Sites/nself/.claude/docs/sport/F04-PLUGIN-INVENTORY-PRO.md` and `F06-BUNDLE-INVENTORY.md` for canonical sources.

## Troubleshooting

- [[Troubleshooting]] — common errors by symptom: backend connection, plugin license, FFI load, push notifications, platform-specific issues

## Contributing

- [[Contributing]] — dev setup, code style, PR process, testing

## Resources

- [GitHub: nself-org/nclaw](https://github.com/nself-org/nclaw) — this repo
- [claw.nself.org](https://claw.nself.org) — ɳClaw product page (separate `web/claw/` site)
- [nself.org](https://nself.org) — ɳSelf platform
- [nself.org/pricing](https://nself.org/pricing) — pro plugin licensing
- [Changelog](Changelog) — version history
