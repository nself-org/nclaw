# Build ɳClaw for macOS

Build a universal binary (arm64 + x86_64) for Intel and Apple Silicon Macs.

## Prerequisites

- Xcode 14+ with Command Line Tools: `xcode-select --install`
- Apple Developer account (Team ID from developer.apple.com)
- Code-signing certificate: "Apple Development" or "Apple Distribution"
- Notarization credentials: Apple ID + app-specific password

## Build Universal Binary

```bash
cd nclaw/desktop
pnpm tauri build --target universal-apple-darwin
```

This creates a single `.app` bundle containing both arm64 and x86_64 code.

## Sign and Notarize

Tauri auto-signs during build if your certificate is in Keychain. For notarization (required for distribution outside App Store):

```bash
xcrun notarytool submit \
  nclaw/desktop/src-tauri/target/universal-apple-darwin/release/bundle/dmg/ɳClaw_1.1.1_universal.dmg \
  --apple-id aric.camarata@gmail.com \
  --team-id $(security find-identity -v -p codesigning | grep "Apple Development" | awk '{print $NF}' | tr -d '()') \
  --password <app-specific-password>
```

Wait ~10 min for notarization; query status via `xcrun notarytool info <request-uuid>`.

## Output

- **DMG installer:** `desktop/src-tauri/target/universal-apple-darwin/release/bundle/dmg/ɳClaw_1.1.1_universal.dmg`
- **App bundle:** `desktop/src-tauri/target/universal-apple-darwin/release/bundle/macos/ɳClaw.app`

Users install via DMG drag-and-drop into `/Applications/`.

## Troubleshooting

1. **"Code-signing identity not found"** — Run `security find-identity -v -p codesigning` and verify your cert is listed. Import from .p12 if missing.
2. **"Notarization request timed out"** — Increase timeout: `xcrun notarytool submit ... --wait` (default 120s).
3. **"x86_64 architecture missing"** — Verify Rosetta 2 is installed: `softwareupdate -i -a`. Re-run build.
4. **"Xcode CLI Tools outdated"** — Run `xcode-select --install` to update.
5. **"mkcert CA prompt during build"** — Trust the CA first: `mkcert -install` (unrelated to app certs, but blocks build if Xcode tries to fetch resources over HTTPS).

---

Verified on: 2026-05-13 — author bench
