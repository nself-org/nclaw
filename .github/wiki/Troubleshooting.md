# Troubleshooting

Common errors when running, building, or using ɳClaw, with fixes.

By the end of this page you will:

- Know how to diagnose backend connection issues, plugin license errors, FFI build failures, and platform-specific runtime issues.
- Have a quick reference for the most frequent errors by symptom.

## Prerequisites

- A working install per [[Getting-Started]].
- Backend running per [[Backend Setup section in Getting-Started]].
- Pro license set per [[Plugin Requirements section]].

## Steps — Diagnose by symptom

### Backend connection refused

**Symptom:** App shows "Cannot reach server" or "Connection refused".

**Diagnose:**

```bash
nself status
```

**Cause and fix:**

- If services show "stopped": run `nself start`.
- If services show "running" but app still fails: check the URL the app is configured with. It must match the nginx-proxied URL (typically `http://localhost` for local dev, or your domain in prod). Never use a direct port like `:8080`.
- Firewall blocking: ensure ports 80/443 (nginx) are open.

### "License tier insufficient" on plugin install

**Symptom:** `nself plugin install ai claw mux` returns an error mentioning license tier.

**Diagnose:**

```bash
nself license info
```

**Cause and fix:**

- The current key's tier is below `Pro` ($1.99/mo). The `ai` and `claw` plugins are `max` tier (per F04).
- Set a higher-tier key: `nself license set nself_pro_<your_key>`.
- If you don't have one yet, get one at [nself.org/pricing](https://nself.org/pricing).

### Plugin not found

**Symptom:** App reports "Plugin 'claw' not available" or similar.

**Diagnose:**

```bash
nself plugin list
```

**Cause and fix:**

- Plugin was never installed. Run `nself plugin install ai claw mux`.
- Plugin was installed but `nself build` was not re-run. Run `nself build && nself restart`.

### libnclaw load fails on iOS

**Symptom:** App crashes on launch with `dyld: Library not loaded` or "Failed to lookup symbol".

**Diagnose:**

```bash
ls libs/libnclaw/target/aarch64-apple-ios/release/
```

**Cause and fix:**

- libnclaw was not built for the iOS target. Run the iOS build steps from [[libnclaw-Dev-Guide]] or [[iOS-Build-Guide]].
- Built library was not embedded in the Xcode project. In Xcode > Build Phases > Link Binary With Libraries, verify libnclaw is listed.

### libnclaw load fails on Android

**Symptom:** `java.lang.UnsatisfiedLinkError: dlopen failed: library libnclaw.so not found`.

**Diagnose:**

```bash
ls app/android/app/src/main/jniLibs/
```

**Cause and fix:**

- jniLibs directory is missing native libraries for the device's ABI.
- Re-run `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 -o app/android/app/src/main/jniLibs build --release` from `libs/libnclaw/`.

### Push notifications not arriving

**Symptom:** No push notifications even though `nself-notify` is installed.

**Diagnose:**

- iOS: Check Console.app for APNs delivery errors.
- Android: `adb logcat | grep -i fcm`

**Cause and fix:**

- iOS: APNs auth key not configured in `nself-notify` plugin. Generate at Apple Developer > Certificates, upload to plugin config.
- Android: `google-services.json` missing or wrong package name. Re-download from Firebase console.
- Push capability not enabled in app build (Xcode Capabilities tab for iOS).

### Hot reload doesn't pick up Rust changes

**Symptom:** Edited `libs/libnclaw/src/...`, ran hot reload, no change in app behavior.

**Cause:** Flutter hot reload only reloads Dart code. Native libraries are loaded once.

**Fix:** Rebuild libnclaw (`cargo build --release`), full restart the Flutter app. For iOS, also `pod install` if FFI bindings regenerated.

### Web build crashes on FFI call

**Symptom:** App on web throws `LibnclawNotAvailableException` when calling crypto.

**Cause:** Flutter web cannot load native libraries via `dart:ffi`.

**Fix:** Use the WASM stub or REST proxy fallback. See [[Web-Build-Guide]] for details.

### macOS app shows "App is damaged"

**Symptom:** Users see "App is damaged and can't be opened" after downloading the DMG.

**Cause:** DMG is not notarized, or the notarization ticket is not stapled.

**Fix:** Re-notarize via `xcrun notarytool submit ... --wait`. After status `Accepted`, run `xcrun stapler staple <dmg>`. See [[macOS-Build-Guide]].

### Memory not capturing turns

**Symptom:** Sidebar topics don't update after conversations.

**Diagnose:**

```bash
docker logs nself-claw 2>&1 | grep -i memory
```

**Cause and fix:**

- `claw` plugin is missing or not running. Check `nself plugin list` and `nself status`.
- `mux` plugin is missing (required for topic detection). Install: `nself plugin install mux`.
- Memory feature is disabled. Check the `CLAW_MEMORY_ENABLED` env var (should be `true` by default).

### Persona switch not persisting

**Symptom:** Selecting a different persona resets after app restart.

**Cause:** Persona is not stored to `FlutterSecureStorage` correctly, or the load on startup is missing.

**Fix:** Verify `personaProvider` reads the saved value on init. Check `FlutterSecureStorage` is permitted by the platform (entitlements on macOS, Keychain access on iOS).

### "Untrusted Developer" on iOS first launch

**Symptom:** App installs on a physical iOS device but launches to "Untrusted Developer".

**Fix:** Settings > General > VPN & Device Management > tap your developer profile > Trust. Then re-launch the app.

### Onboarding completes but chat fails

**Symptom:** Onboarding flow ends successfully, but the first message fails to send.

**Diagnose:**

```bash
docker logs nself-claw 2>&1 | tail -50
```

**Cause and fix:**

- License key entered during onboarding is invalid. Check key prefix `nself_pro_` and length (32+ chars).
- Backend `claw` plugin is not running. Run `nself status` and `nself restart claw`.
- Network/CORS issue. On web, check browser DevTools Network tab for CORS errors.

## Verification

After applying a fix, verify the affected flow end-to-end:

- Backend: `nself status` shows all required services running.
- Plugins: `nself plugin list` includes `ai`, `claw`, `mux`.
- App: launch and send a test message. Streaming response confirms the full pipeline works.

## Next Steps

- [[Getting-Started]] — fresh install / reinstall
- [[Architecture-Deep-Dive]] — system architecture (helps locate issues by layer)
- [[E2E-Encryption]] — encryption-specific issues
- [[Backend Setup section in Getting-Started]] — backend recovery

← [[Home]] | [[Home]] →
