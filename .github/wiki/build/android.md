# Build ɳClaw for Android

Build and deploy to Google Play via Flutter Android.

## Prerequisites

- Flutter SDK with Android toolchain: `flutter doctor`
- Android SDK API 34+, NDK r26+ (via Android Studio's SDK Manager)
- Keystore file (JKS or PKCS12) — use Play App Signing (Google manages final signing cert)
- Google Play Developer account + app registered

## Build App Bundle

```bash
cd nclaw/mobile
flutter build appbundle --release
```

Set signing credentials in `android/gradle.properties`:

```properties
KEYSTORE_PATH=../path/to/keystore.jks
KEYSTORE_PASSWORD=<password>
KEY_ALIAS=upload-key
KEY_PASSWORD=<password>
```

## Upload to Google Play

Upload the AAB to Google Play Console → Your App → Testing → Internal testing (or Production after testing):

```bash
# Manual via Google Play Console
# File: mobile/build/app/outputs/bundle/release/app-release.aab
```

Or use bundletool CLI (advanced):

```bash
bundletool build-apks \
  --bundle=mobile/build/app/outputs/bundle/release/app-release.aab \
  --output=app.apks \
  --ks=keystore.jks \
  --ks-pass=pass:<password> \
  --ks-key-alias=upload-key \
  --key-pass=pass:<password>
```

## Output

- **AAB (App Bundle):** `mobile/build/app/outputs/bundle/release/app-release.aab`
- Google Play handles final signing and APK generation per device config.

## Troubleshooting

1. **"NDK version mismatch"** — Ensure r26+: Android Studio → SDK Manager → NDK. Update `android/app/build.gradle` if pinned.
2. **"Keystore password environment variable missing"** — Export: `export KEYSTORE_PASSWORD=<pwd>` before build.
3. **"ABI split errors"** — Disable for bundle: `bundleRelease { enableSplit = false }` in build.gradle.
4. **"FRB Android JNI build fails"** — Regenerate: `cd mobile && dart run build_runner build --release`.
5. **"sqlite-vec aarch64/armv7 libs missing"** — Precompiled .so files must be in `android/app/src/main/jniLibs/`. Verify ndkVersion matches compilation target.

---

Verified on: 2026-05-13 — author bench
