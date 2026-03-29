# Changelog

All notable changes to nClaw clients are documented here.

## Unreleased

## v1.0.0 — 2026-03-29

First stable release. Marks nClaw as production-ready alongside the nSelf CLI v1.0.0 LTS launch.

### Documentation
- Created `.github/wiki/` with full documentation suite (architecture, API, setup guides)
- Expanded README with architecture overview, quickstart, and feature matrix
- Added PR template, CONTRIBUTING guide, and SECURITY policy
- Expanded backend self-hosting guide

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
