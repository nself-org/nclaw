# Build ɳClaw for iOS

> **Legacy page.** It describes the archived Flutter mobile app (`mobile-flutter-archive/`). The mobile app is being rebuilt on React Native + Expo under P8-CLAW; do not use these steps for new work.

Build and deploy to App Store or TestFlight via Flutter iOS.

## Prerequisites

- macOS with Xcode 14+
- iOS Developer enrollment (Apple Developer account)
- Bundle ID: `org.nself.nclaw` — confirm in `mobile/ios/Runner.xcodeproj`
- Team ID from developer.apple.com
- Provisioning profile with capabilities: Push Notifications, HealthKit (if enabled)

## Build Release IPA

```bash
cd nclaw/mobile
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

Create `ios/ExportOptions.plist` (if missing):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>teamID</key>
  <string>YOUR_TEAM_ID</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>method</key>
  <string>app-store</string>
</dict>
</plist>
```

## Upload to TestFlight or App Store

**TestFlight (internal testing):**

```bash
xcrun altool --upload-app \
  --file "mobile/build/ios/ipa/nclaw.ipa" \
  --type ios \
  --apple-id aric.camarata@gmail.com \
  --password <app-specific-password>
```

Or use Transporter GUI: `open /Applications/Transporter.app`

**App Store (production):**
Submit via App Store Connect after TestFlight approval; same IPA file.

## Output

- **IPA file:** `mobile/build/ios/ipa/nclaw.ipa`
- **Bitcode:** Deprecated (iOS 14+); Xcode auto-disables.

## Troubleshooting

1. **"Provisioning profile not found"** — Ensure bundle ID matches profile in App Store Connect. Regenerate: Xcode → Signing & Capabilities.
2. **"Code-signing certs not in Keychain"** — Download from Apple Developer → Certificates. Import `.cer` and `.p8` files.
3. **"Bitcode compilation error"** — Update the Flutter toolchain of the archived app: `flutter upgrade`. Bitcode support was removed in iOS 14.
4. **"FRB iOS framework missing"** — Regenerate: `cd mobile && dart run build_runner build --release`.
5. **"sqlite-vec iOS lib build fails"** — Use precompiled XCFramework; verify `ios/Pods/sqlite-vec/` exists.

---

Verified on: 2026-05-13 — author bench
