# Changelog

## Unreleased

## v0.9.9

- Tauri desktop companion finalized (imports, Flutter geolocator, README structure)
- Phase 65C: ambient context, voice input, sensors, sandbox filesystem, iOS OAuth PKCE
- Added `build-release.yml` workflow for Flutter APK, macOS DMG, and GitHub Release (T-2430)
- Phase 65: iOS Keychain auth, Gradle fixes, PRI update
- Phase 64: CI expansion, TODO resolution, libnclaw verification
- Phase 61: desktop companion JWT auth, browser automation, OS control, sensor streaming
- Phase 60: Android client updates and desktop companion scaffold
- Removed `apps/web/` — web UI lives in `plugins-pro/claw-web`

## v0.9.9-rc3

- Native apps finalized (iOS, Android, macOS)
- Phase 55: Tauri companion, CI workflow, iOS and Android scaffolds
- Widget tests moved to correct Flutter project location
- Chrome CDP module, browser routes (T-1412), and browser consent (T-1413)
- Phase 224: companion daemon; Phase 228: onboarding flow
- Desktop first-run onboarding and pairing flow
- Generated missing golden test baseline images
- macOS OAuth window with Sign in with Apple and Sign in with Google
- WebSocket switched to NWConnection with HTTP/1.1 ALPN; sandbox default fixed to home directory
- `SubThreadScreen`, `BreakoutSuggestionBanner`, `ThreadTagChips` (T-1107, T-1108)

---

Versions follow [Semantic Versioning](https://semver.org/). For the full commit history, run:

```bash
git log --oneline
```
