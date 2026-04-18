# Build ɳClaw for iOS

By the end of this guide you will:

- Have ɳClaw running on a physical iOS device or simulator.
- Have a working development signing certificate and provisioning profile.

## Prerequisites

- macOS 14+ (Sonoma) with Xcode 15+ installed (`xcodebuild -version`).
- CocoaPods 1.13+ (`pod --version`). Install: `sudo gem install cocoapods`.
- Flutter 3.x (`flutter --version`). Install: see [docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install).
- Rust stable toolchain for libnclaw (`rustc --version`). Install: [rustup.rs](https://rustup.rs/).
- Apple Developer account ($99/yr) with a registered Bundle ID.
- A physical iOS device (iOS 16+) or iOS Simulator.
- A pro license key (ɳClaw Bundle, $0.99/mo) — see the [README](https://github.com/nself-org/nclaw#readme) Requirements section.

## Steps

### Step 1 — Clone and install Flutter dependencies

Clone the repo and pull Dart packages.

```bash
git clone https://github.com/nself-org/nclaw.git
cd claw/app
flutter pub get
```

Expected output:

```
Got dependencies!
```

### Step 2 — Build libnclaw for iOS

The Rust FFI library must be cross-compiled for iOS device + simulator.

```bash
cd ../libs/libnclaw
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
```

Expected output (per target):

```
Compiling libnclaw v0.1.0
Finished `release` profile [optimized] target(s)
```

### Step 3 — Install CocoaPods

```bash
cd ../../app/ios
pod install
```

Expected output ends with:

```
Pod installation complete!
```

### Step 4 — Open in Xcode and configure signing

```bash
open Runner.xcworkspace
```

In Xcode:
- Select the `Runner` target → Signing & Capabilities tab.
- Set your Team (Apple Developer account).
- Confirm or set a unique Bundle Identifier.
- Enable "Automatically manage signing" for development.
- For Push Notifications: Capabilities tab → add "Push Notifications" and "Background Modes" → Remote notifications.

### Step 5 — Build and run

For a connected device:

```bash
cd ..
flutter run -d <device-id> --release
```

List devices first if needed:

```bash
flutter devices
```

For an IPA build (no signing):

```bash
flutter build ios --release --no-codesign
```

Expected output:

```
Built build/ios/iphoneos/Runner.app (xx.xMB)
```

### Step 6 — Distribution

For TestFlight: Xcode > Product > Archive. Upload the archive via the Organizer.

For App Store: same archive flow, then submit for review via App Store Connect.

## Verification

```bash
flutter devices
```

Your iOS device or simulator should be listed. After `flutter run`, ɳClaw should launch. On a physical device, you may need to trust the developer profile: Settings > General > VPN & Device Management > Trust.

After launch, walk through onboarding:

- Connect to your nSelf backend (manual URL, QR code, or short code).
- Enter your license key.
- Send a test message. The streaming response confirms backend connectivity.

## Troubleshooting

### "No matching provisioning profile"

**Symptom:** Xcode reports a missing provisioning profile during build.
**Cause:** Bundle ID is not registered for your Team, or signing is set to Manual.
**Fix:** In Xcode > Signing & Capabilities, set your Team and check "Automatically manage signing". Confirm the Bundle ID is unique.

### libnclaw symbols missing

**Symptom:** Linker error referencing `_libnclaw_*` or `_nclaw_*` symbols.
**Cause:** libnclaw was not built for the target architecture, or the framework was not linked.
**Fix:** Re-run the targeted `cargo build --release --target ...` from `libs/libnclaw/`. Verify the `.a` outputs exist under `target/<arch>/release/`.

### "Untrusted Developer" on first device launch

**Symptom:** App installs but launches to an "Untrusted Developer" screen.
**Cause:** iOS requires the user to trust sideloaded developer profiles.
**Fix:** Settings > General > VPN & Device Management > tap your developer profile > Trust. Then re-launch the app.

### Push notifications don't arrive

**Symptom:** No push notifications even though the `nself-notify` plugin is installed.
**Cause:** APNs auth key is not configured in `nself-notify`, or Push Notifications capability is not enabled in Xcode.
**Fix:** Generate an APNs auth key in Apple Developer > Certificates > Keys; upload it to your `nself-notify` plugin config. Verify the Push Notifications capability is checked in Xcode.

## Next Steps

- [[Android-Build-Guide]] — build for Android
- [[macOS-Build-Guide]] — build for macOS
- [[libnclaw-Dev-Guide]] — work on the Rust FFI library
- [[Troubleshooting]] — common errors across platforms

← [[Home]] | [[Home]] →
