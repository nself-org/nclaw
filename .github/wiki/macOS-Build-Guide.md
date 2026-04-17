# Build ɳClaw for macOS

By the end of this guide you will:

- Have ɳClaw running on macOS as a native app.
- Have a signed and notarized DMG ready for distribution.

## Prerequisites

- macOS 14+ (Sonoma) with Xcode 15+ installed.
- Flutter 3.x (`flutter --version`).
- Rust stable toolchain (`rustc --version`).
- Apple Developer ID Application certificate (paid Apple Developer account).
- App-specific password for `xcrun notarytool` (generated at appleid.apple.com).
- (Optional) `create-dmg` for DMG packaging: `brew install create-dmg`.

## Steps

### Step 1 — Install Flutter dependencies

```bash
cd claw/app
flutter pub get
```

### Step 2 — Build libnclaw as a universal binary

macOS desktop ships as a universal binary supporting both Apple Silicon and Intel.

```bash
cd ../libs/libnclaw
rustup target add aarch64-apple-darwin x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

# Combine into a universal binary
lipo -create \
  target/aarch64-apple-darwin/release/libnclaw.dylib \
  target/x86_64-apple-darwin/release/libnclaw.dylib \
  -output target/libnclaw-universal.dylib
```

Expected output:

```
(no output from lipo on success)
```

Verify:

```bash
file target/libnclaw-universal.dylib
```

Expected: `Mach-O universal binary with 2 architectures`.

### Step 3 — Build the Flutter macOS app

```bash
cd ../../app
flutter build macos --release
```

Expected output:

```
Built build/macos/Build/Products/Release/ɳClaw.app
```

### Step 4 — Code signing

```bash
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  --entitlements macos/Runner/Release.entitlements \
  build/macos/Build/Products/Release/ɳClaw.app
```

Required entitlements (in `macos/Runner/Release.entitlements`):

- `com.apple.security.network.client` — outbound HTTPS to backend
- `com.apple.security.device.audio-input` — voice input
- `com.apple.security.files.user-selected.read-write` — file picker (tool calls)
- `com.apple.security.cs.allow-jit` — Flutter runtime
- `com.apple.security.cs.allow-unsigned-executable-memory` — Flutter runtime

Verify signing:

```bash
codesign --verify --verbose=2 build/macos/Build/Products/Release/ɳClaw.app
```

Expected: `valid on disk`, `satisfies its Designated Requirement`.

### Step 5 — Package the DMG

Use the helper script:

```bash
cd ..
./scripts/build-dmg.sh
```

Or manually:

```bash
create-dmg --volname "ɳClaw" --window-size 600 400 \
  --icon "ɳClaw.app" 150 200 --app-drop-link 450 200 \
  build/ɳClaw.dmg \
  build/macos/Build/Products/Release/ɳClaw.app
```

Expected output: `created: build/ɳClaw.dmg`.

### Step 6 — Notarize and staple

```bash
./scripts/notarize-macos.sh build/ɳClaw.dmg
```

Or manually:

```bash
xcrun notarytool submit build/ɳClaw.dmg \
  --apple-id "you@example.com" \
  --team-id TEAMID \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait
```

Expected (after Apple completes notarization, typically 5-30 min):

```
status: Accepted
```

Staple the ticket so the DMG works offline:

```bash
xcrun stapler staple build/ɳClaw.dmg
```

Expected:

```
The staple and validate action worked!
```

### Step 7 — Distribution via Sparkle update channel

The repo includes Sparkle update feed generation:

```bash
./scripts/generate-update-feeds.sh
```

This produces an `appcast.xml` for the Sparkle framework so existing installs auto-update.

## Verification

```bash
spctl --assess --type install build/ɳClaw.dmg
```

Expected:

```
build/ɳClaw.dmg: accepted
source=Notarized Developer ID
```

Mount and launch:

```bash
hdiutil attach build/ɳClaw.dmg
open "/Volumes/ɳClaw/ɳClaw.app"
```

The app should launch without "App is damaged" or Gatekeeper warnings.

## Troubleshooting

### "App is damaged and can't be opened"

**Symptom:** Users see this Gatekeeper error after downloading the DMG.
**Cause:** The DMG is not notarized or the notarization ticket is not stapled.
**Fix:** Run `xcrun notarytool submit ... --wait` and verify status `Accepted`. Then `xcrun stapler staple <dmg>`.

### "spctl rejected"

**Symptom:** `spctl --assess` reports the DMG is rejected.
**Cause:** Hardened runtime is missing (`--options runtime` was not passed to codesign), or entitlements are wrong.
**Fix:** Re-codesign with `--options runtime` and the correct entitlements file. Re-notarize.

### Notarization "status: Invalid"

**Symptom:** Notarization completes with status `Invalid`.
**Cause:** Common issues: missing hardened runtime, unsigned helper binaries, executables outside the bundle.
**Fix:** Read the notarization log: `xcrun notarytool log <submission-id> --apple-id ... --team-id ... --password ...`. Fix issues and resubmit.

### libnclaw not found at runtime

**Symptom:** App launches but crashes with `dyld: Library not loaded: @rpath/libnclaw.dylib`.
**Cause:** The dylib is not in the app bundle's Frameworks directory or rpath is wrong.
**Fix:** Verify `ɳClaw.app/Contents/Frameworks/libnclaw.dylib` exists. Set rpath: `install_name_tool -add_rpath @executable_path/../Frameworks ...`.

## Next Steps

- [[iOS-Build-Guide]] — build for iOS
- [[Web-Build-Guide]] — build for Web
- [[Desktop-Build-Guide]] — build for Linux + Windows desktop
- [[Troubleshooting]] — common errors across platforms

← [[Home]] | [[Home]] →
