# Changelog

All notable changes to nClaw clients are documented here.

## v1.2.0 — PENDING (v1.1.0 ecosystem release)

Minor release. ɳClaw bundle updated to 14 plugins. New mcp and knowledge-base plugins. claw.nself.org multi-tenant managed launch.

### Added

- **`mcp` plugin integration**: Model Context Protocol plugin (from ɳClaw bundle) now installable with `nself bundle install claw`. Enables external MCP server connections from the ɳClaw assistant.
- **`knowledge-base` plugin integration**: persistent knowledge base plugin for long-term memory extraction and retrieval.
- **claw.nself.org SaaS launch**: multi-tenant managed ɳClaw available at `claw.nself.org` (web/nclaw) for users who don't want to self-host.
- **`nself bundle install claw` support**: install all 14 ɳClaw bundle plugins (ai, claw, claw-web, mux, voice, browser, google, notify, cron, claw-budget, claw-news, mcp, knowledge-base + free companion tokens) in one command.
- **Bundle pricing UI**: in-app upgrade prompt shows ɳClaw bundle at $0.99/mo / $9.99/yr.

### Changed

- ɳClaw bundle expanded from 12 to 14 plugins (added mcp, knowledge-base).
- Minimum nSelf CLI version: v1.1.0.
- libnclaw: protocol version bumped to match new plugin capabilities.

---

## Unreleased

### Fixed

- ci: relax `build_runner` constraint to `^2.4.0` to match pubspec.lock and resolve version conflict with current Flutter stable (S26 T03)
- ci: add `workflow_dispatch` trigger to CI and Flutter CI workflows for manual re-runs

## v1.0.0 — 2026-03-29

First stable release. Production-ready alongside nSelf CLI v1.0.0 LTS. All core features are complete and tested across all four platforms (iOS, Android, macOS, web).

### AI Chat

- Multi-turn conversations with full context management and streaming responses
- Conversation branching — fork any message into a sub-thread with breadcrumb navigation
- Message editing and regeneration
- Automatic context window management — older messages are summarized and compressed near the token limit
- Server-side session persistence via `np_claw_sessions`; thread list with tags, project grouping, and full-text search

### Memory and Context

- Persistent memory across sessions — the AI remembers user preferences, prior interactions, and stated facts
- Memory entries viewable, editable, and deletable from the Memories UI on all platforms
- Context injection — pin knowledge entries to include in every conversation
- Proactive memory suggestions surface relevant past context automatically

### Tool Calls

- AI can invoke tools and chain multiple calls in a single turn; results are fed back automatically
- **Web search** — search the web and retrieve structured results
- **File read/write** — read and write files on the backend host
- **Code execution** — run code in a sandboxed environment
- **Shell commands** — execute commands on the backend host (with user approval)
- **Browser automation** — control a real Chrome browser via `nself-browser` (Chrome DevTools Protocol)
- **Calendar/email** — connect to external services via `nself-mux`
- Agent queue protocol — actions queued offline and dispatched on reconnect; `libnclaw` protocol and types v2

### Personas

- Custom AI personas with defined names, avatars, system prompts, and behavior rules
- Per-persona model selection, topic scope restrictions, and communication style preferences
- Personas can be shared with other users on the same backend instance

### Proactive Intelligence

- Background agents that monitor events and act without being explicitly asked
- **Scheduled tasks** — run prompts or workflows on a cron-style schedule
- **Event triggers** — react to file changes, calendar events, and incoming messages
- **Digest generation** — periodic summaries of monitored feeds
- **Alerts** — notify when defined conditions are met (push notification via `nself-notify`)

### Voice

- Speech-to-text input via `nself-voice` Pro plugin — real-time transcription displayed as you speak
- Text-to-speech playback with configurable speed and voice selection; per-message play button
- Continuous voice conversation mode — full-screen hands-free loop with silence detection
- Web client voice input via Web Speech API — hold-to-speak mic button
- `VoiceSettingsScreen` — STT/TTS configuration persisted locally and synced to the backend

### Browser Automation

- AI-driven browser control via `nself-browser` Pro plugin (Chrome DevTools Protocol)
- Navigate URLs, click elements, fill forms, capture screenshots, execute JavaScript
- Visual reasoning — AI interprets screenshots to make decisions during automated workflows
- Browser consent UI — user approves automation session before any CDP connection is opened

### Multi-Modal Input

- **Images** — camera capture or photo library; AI describes and reasons over images
- **Files** — PDFs, documents, and source files attached as conversation context
- **Audio** — voice notes transcribed before sending (distinct from live voice mode)

### Desktop Companion (Tauri)

- macOS menu bar daemon — background process for ambient context capture and server pairing
- First-run onboarding flow with guided server pairing
- OS control and sensor streaming (clipboard, screen, input events)
- Chrome CDP module with full browser automation routes
- JWT authentication with macOS Keychain credential storage
- Sign in with Apple and Sign in with Google via native OAuth window
- WebSocket transport upgraded to `NWConnection` for HTTP/1.1 ALPN compatibility

### E2E Encryption

- Optional end-to-end encryption via `libnclaw`
- X25519 Diffie-Hellman key exchange; XChaCha20-Poly1305 authenticated encryption
- Message content encrypted on-device before reaching the backend — server stores only ciphertext
- Keys stored in platform keychain: iOS Keychain, Android Keystore, macOS Keychain

### Platform Support

- **Flutter app** (`app/`) — single codebase targeting iOS 16+, Android 10+ (API 29+), macOS 12+, and web
- **SwiftUI native client** (`apps/ios/`) — iOS and macOS via Mac Catalyst
- **Kotlin native client** (`apps/android/`) — Jetpack Compose, Android 10+
- **Tauri desktop companion** (`apps/desktop/`) — macOS daemon for ambient context and browser automation
- **Web client** — full nClaw web app served from `plugins-pro/claw-web` (moved from `apps/web/` in v0.9.9)

### libnclaw (Rust FFI)

- Single source of truth for all shared types, protocol definitions, and encryption
- FFI bindings generated for Dart (`dart:ffi`), Swift (`@_cdecl` C ABI), and Kotlin (JNI)
- Agent queue protocol types and offline action serialization
- E2E encryption primitives: X25519 key generation, XChaCha20-Poly1305 encrypt/decrypt

### CI / Release

- `build-release.yml` — produces Flutter APK, macOS DMG, and GitHub Release artifacts
- CI matrix covering iOS simulator, Android emulator, macOS, and web builds
- Golden test comparator with 1% pixel-diff threshold for cross-platform rendering tolerance

### Documentation

- `.github/wiki/` with full documentation suite: Architecture, Features, Getting Started, Contributing, Changelog
- Expanded README with architecture overview, quickstart, and feature matrix
- PR template, CONTRIBUTING guide, and SECURITY policy
- Backend self-hosting guide with environment variable reference and plugin setup walkthrough

### Bug Fixes

- Fixed `dependencyResolutionManagement` block in Android Gradle for compatibility with newer Gradle versions

---

## v0.9.9 — 2026-03-24

Desktop companion finalized. Ambient context, voice sensors, and iOS OAuth PKCE shipped. Release workflow added.

### Features
- Phase 65C: ambient context capture, voice input, device sensors, sandbox filesystem access, iOS OAuth PKCE flow
- Added `build-release.yml` CI workflow — produces Flutter APK, macOS DMG, and GitHub Release artifacts (T-2430)

### Bug Fixes
- Phase 66: fixed Tauri import paths, added Flutter `geolocator` dependency, corrected README structure
- Phase 65: iOS Keychain auth storage, Gradle configuration fix, PRI update
- Phase 64: expanded CI matrix, resolved outstanding TODOs, verified libnclaw FFI bindings
- Fixed `_ThresholdComparator` basedir double-strip in golden test comparator
- Relaxed golden test pixel diff threshold to 1% to tolerate cross-platform CI rendering variance

### Internal
- Removed `apps/web/` — web UI moved to `plugins-pro/claw-web` plugin

---

## v0.9.9-rc3 — 2026-03-19

Native apps finalized for iOS, Android, and macOS. Desktop companion daemon shipped with browser automation, OS control, and sensor streaming.

### Features
- Phase 61: desktop companion — JWT auth, Chrome CDP browser automation, OS control, sensor streaming
- Phase 60: Android client updates and desktop companion scaffold
- Phase 55: Tauri companion scaffold, CI workflow, iOS and Android project scaffolds
- Phase 224: companion daemon process management
- Phase 228: first-run onboarding flow for desktop companion
- Desktop first-run onboarding and server pairing flow
- macOS OAuth window with Sign in with Apple and Sign in with Google
- Chrome CDP module, browser automation routes (T-1412), and browser consent UI (T-1413)
- `SubThreadScreen`, `BreakoutSuggestionBanner`, `ThreadTagChips` Flutter widgets (T-1107, T-1108)

### Bug Fixes
- Switched macOS WebSocket from `URLSession` to `NWConnection` with HTTP/1.1 ALPN negotiation
- Fixed sandbox default directory to user home instead of app bundle path
- Moved Flutter widget tests to correct project location

---

## v0.9.9-rc2 — 2026-03-15

Full voice pipeline, thread/project organisation, memories UI, web app, and agent queue protocol shipped.

### Features

**Voice**
- T-1109: `SttService` — speech-to-text with mic permissions on iOS, Android, and macOS
- T-1110: `TtsService` with `flutter_tts` and markdown stripping before playback
- T-1111: `VoiceChatWidget` — push-to-talk, tap-toggle, waveform visualiser
- T-1112: TTS auto-play on assistant messages and per-message play button
- T-1113: Continuous voice conversation mode — full-screen hands-free loop
- T-1115: `VoiceSettingsScreen` — STT/TTS configuration, persistence, server sync
- T-1117: Server-side TTS via `nself-voice` plugin in `TtsService`
- T-1120: Voice input in web client via Web Speech API — hold-to-speak mic button

**Organisation**
- T-1104: `ChatProvider` updated to use `np_claw_sessions` server-side session storage
- T-1105: `ThreadListScreen` — session list with tags, project grouping, and search
- T-1106: `ProjectListScreen` — project CRUD with colour and emoji picker
- T-1107: `SubThreadView` — branch conversation from any message, breadcrumb trail, ↳ indicator
- T-1108: `BreakoutSuggestionBanner` and `SessionTagsBar` with `initialTagFilter`
- T-1121: Thread/project sidebar — grouped sessions, collapsible projects, context menu

**Web client (Phase 148 + 163 + 187)**
- Full nClaw web app with memories and proactive settings pages
- T-1119: Admin panel — service status dashboard, metrics, natural language query, audit log
- Fixed inline styles and ARIA issues across web components and proactive settings page

**Flutter mobile/desktop (Phase 146/147/185/186)**
- Chat screen, onboarding wizard, usage dashboard, bottom navigation
- Push notifications integration
- Memories UI

**Agent protocol**
- T-0950: Agent queue protocol — offline action queuing, `libnclaw` protocol and types v2
- T-1070: Widget tests for `ChatScreen` and `OnboardingScreen`

### Bug Fixes
- T-1064: Surface `shell-unsupported` errors via `debugPrint` before sending notification
- Upgraded `mobile_scanner` 5 → 7 to resolve CocoaPods conflict on iOS
- Updated `PairingScreen` widget test to match current UI text
- Resolved `flutter analyze` warnings — doc comment HTML entities, lint suppressions
- Fixed Dart 3.7 null-aware map entry syntax (`?state`) and `_` wildcard in `separatorBuilder`
- Removed broken golden test file and empty test directory

---

## v0.9.9-rc1 — 2026-03-12

Initial client scaffolding — Flutter app, macOS daemon, OAuth, action queue, and CI infrastructure.

### Features
- Flutter app scaffold: action queue UI with offline persistence, OAuth WebView bridge
- `ActionExecutorService` with action approval loop and WebSocket result dispatch
- macOS menu bar daemon with local HTTP server for companion pairing
- Companion apps scaffold (desktop + mobile) with Flutter CI pipeline
- OAuth WebView bridge and desktop endpoint enhancements
- Native build CI and test infrastructure (iOS simulator, Android emulator)

### Bug Fixes
- Added `pod install` step before iOS build in CI to resolve `url_launcher_ios` dependency

---

## v0.9.0 — 2026-03-06

Project created.

- Initial commit — repository structure established
- Scaffold nClaw client apps repo: `apps/ios/`, `apps/android/`, `app/` (Flutter), `libs/libnclaw/` (Rust), `backend/`

---

Versions follow [Semantic Versioning](https://semver.org/). For the full commit history, run:

```bash
git log --oneline
```

## [1.0.10] - 2026-04-23 (Wave 5)

### Added

- **Flutter auth SDK** (O08) — Flutter auth SDK updated to use unified auth (FF_UNIFIED_AUTH). Session tokens use np_sessions v2 format. AUTH_COOKIE_* env vars respected.
- **Claw BIOS Layers 1+2** (C17) — Backend claw plugin now boots with identity + runtime context layers. nclaw app receives enriched system-prompt responses.


## v1.0.12 (P96 — 2026-04-25)

### Added
- Flutter ship-ready: l10n ARB files generated for all supported locales.
- Brand assets updated to v1.0.12 icon set.
- Auth SDK migration: replaced direct Hasura auth calls with nSelf auth SDK client.

### Fixed
- `web/nclaw/package.json`: added `@nself-web/og` workspace dependency required for Open Graph image generation.
