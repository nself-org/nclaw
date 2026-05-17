# Build ɳClaw for Android

By the end of this guide you will:

- Have ɳClaw running on an Android emulator or physical device.
- Have a working release keystore for Play Store distribution.

## Prerequisites

- Android Studio Hedgehog (2023.1.1) or newer (`Help > About`).
- Android SDK Platform 34 (target) and Build Tools 34.0.0+.
- Android NDK r26b (pinned — matches CI; r26b required for ABI stability with cargo-ndk ≥3.5).
- Flutter 3.x (`flutter --version`).
- Rust stable toolchain (`rustc --version`) with `cargo-ndk`: `cargo install cargo-ndk`.
- JDK 17 (Android Studio bundles this).
- A physical Android device (Android 7.0+, API 24+) with USB debugging, or an Android emulator (API 24+).
- A pro license key (ɳClaw Bundle, $0.99/mo).

## Steps

### Step 1 — Install dependencies

```bash
cd claw/app
flutter pub get
```

Expected output:

```
Got dependencies!
```

### Step 2 — Cross-compile libnclaw for Android ABIs

ɳClaw ships native code for four Android ABIs.

```bash
cd ../libs/libnclaw
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 -o ../../app/android/app/src/main/jniLibs build --release
```

Expected output (per target):

```
Finished `release` profile [optimized] target(s)
```

The `jniLibs` directory will contain `arm64-v8a/libnclaw.so`, `armeabi-v7a/libnclaw.so`, `x86/libnclaw.so`, `x86_64/libnclaw.so`.

### Step 3 — Configure signing keystore (release builds)

For development you can skip this step. For release builds:

```bash
keytool -genkey -v -keystore ~/secure/nclaw-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias nclaw
```

Store the keystore path and passwords in `~/.claude/vault.env`:

```bash
NCLAW_ANDROID_KEYSTORE_PATH=/Users/you/secure/nclaw-release.jks
NCLAW_ANDROID_KEYSTORE_PASSWORD=...
NCLAW_ANDROID_KEY_PASSWORD=...
NCLAW_ANDROID_KEY_ALIAS=nclaw
```

In `app/android/app/build.gradle`, read these from environment via a gitignored `key.properties` file. Never commit the keystore or its passwords.

### Step 4 — Build the Android App Bundle

For a debug APK on a connected device:

```bash
cd ../../app
flutter run -d android --debug
```

For a release App Bundle (Play Store upload):

```bash
flutter build appbundle --release
```

Expected output:

```
Built build/app/outputs/bundle/release/app-release.aab (xx.xMB)
```

### Step 5 — Configure FCM for push notifications

If you want push notifications via the `nself-notify` plugin:

- Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com).
- Add your Android app (Package name matches your Bundle ID).
- Download `google-services.json` and place it at `app/android/app/google-services.json` (gitignored).
- Upload the FCM Server Key to your `nself-notify` plugin config.

### Step 6 — Distribution

Upload the `.aab` to Google Play Console for internal testing, closed testing, or production.

For sideload distribution:

```bash
flutter build apk --release --split-per-abi
```

Produces one APK per ABI under `build/app/outputs/flutter-apk/`.

## Verification

```bash
flutter devices
```

Your Android device or emulator should be listed. After `flutter run`, ɳClaw launches. Check that:

- Onboarding completes (server pair, license, persona).
- Chat sends and streams a response.
- libnclaw loaded successfully (no `UnsatisfiedLinkError` in logcat: `adb logcat | grep -i libnclaw`).

For release builds, verify the APK is signed:

```bash
jarsigner -verify build/app/outputs/flutter-apk/app-release.apk
```

Expected: `jar verified.`

## Troubleshooting

### "UnsatisfiedLinkError: dlopen failed: library libnclaw.so not found"

**Symptom:** App crashes on launch with `java.lang.UnsatisfiedLinkError`.
**Cause:** libnclaw was not cross-compiled for the device's ABI, or jniLibs path is wrong.
**Fix:** Re-run `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 -o ../../app/android/app/src/main/jniLibs build --release`. Verify each ABI directory contains `libnclaw.so`.

### Gradle "minSdkVersion < ...required"

**Symptom:** Build fails with a minSdk version error.
**Cause:** A dependency requires a higher minSdk than the project default.
**Fix:** Open `app/android/app/build.gradle`, set `minSdkVersion 24` (Android 7.0). Lower than 24 is not supported.

### Keystore not found

**Symptom:** `Keystore file '...' not found for signing config 'release'.`
**Cause:** `key.properties` is missing or the keystore path is wrong.
**Fix:** Verify `key.properties` exists alongside `app/android/build.gradle` and points to a valid keystore. Reference `~/.claude/vault.env` for paths.

### FCM tokens not registering

**Symptom:** Device doesn't appear in `nself-notify` registered devices.
**Cause:** `google-services.json` is missing or wrong package name.
**Fix:** Re-download from Firebase console with the exact Bundle ID. Verify `app/android/app/google-services.json` exists. Rebuild with `flutter clean && flutter pub get && flutter build`.

## CI (GitHub Actions)

Android builds run automatically on every PR and push to `main` that touches `nclaw/mobile/**`, `nclaw/core/**`, or `nclaw/android/**`. The CI workflow mirrors these manual steps exactly:

- NDK r26b is pinned via `android-actions/setup-android@v3` with `ndk-version: r26b`.
- cargo-ndk ≥3.5 is installed via the `setup-rust-mobile` composite action (`nclaw/.github/actions/setup-rust-mobile/action.yml`).
- Keystore signing is **conditional**: if `ANDROID_KEYSTORE_BASE64` secret is not set, CI builds an unsigned APK with `--no-shrink` instead.
- The FRB codegen drift gate runs before every platform build — stale bindings fail the build before compilation starts.

See `.github/workflows/mobile-android.yml` for the full CI definition. The matrix orchestrator at `.github/workflows/mobile-matrix.yml` runs all 5 platform builds in parallel.

## Next Steps

- [[iOS-Build-Guide]] — build for iOS
- [[macOS-Build-Guide]] — build for macOS
- [[libnclaw-Dev-Guide]] — work on the Rust FFI library
- [[Troubleshooting]] — common errors across platforms
- [[MOBILE]] — full mobile CI matrix reference

← [[Home]] | [[Home]] →
