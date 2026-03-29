# nClaw Wiki

Welcome to the nClaw documentation. nClaw is an open-source AI assistant client for iOS, Android, macOS, and web — connecting to your own self-hosted nSelf backend.

## Pages

- [Getting Started](Getting-Started) — Prerequisites, backend setup, and running the app
- [Architecture](Architecture) — Component overview, FFI layer, backend integration, data flow
- [Features](Features) — Complete feature list with descriptions
- [Contributing](Contributing) — Dev setup, code style, PR process, testing
- [Changelog](Changelog) — Version history

## Overview

nClaw is the client-side of the nClaw AI assistant platform. It is an open-source reference app that you self-host — nSelf does not run any hosted version of this app.

**Key facts:**

- Flutter app for iOS, Android, macOS, and web (plus native SwiftUI and Kotlin clients)
- Requires a self-hosted nSelf backend with Pro plugins: `ai`, `claw`, `mux`, `voice`, `browser`
- All logic shared through `libnclaw` — a Rust FFI library for types, protocol, and E2E encryption
- MIT licensed; Pro plugins require a separate nSelf license key

**Links:**

- [nself.org](https://nself.org) — nSelf infrastructure platform
- [claw.nself.org](https://claw.nself.org) — nClaw product page
- [GitHub: nself-org/claw](https://github.com/nself-org/claw) — this repo
- [nself.org/pricing](https://nself.org/pricing) — Pro plugin licensing
