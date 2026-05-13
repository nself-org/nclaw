# Build ɳClaw from Source

This directory contains platform-specific guides for building ɳClaw on macOS, Windows, Linux, iOS, and Android.

## Platform Matrix

| Platform | Guide | Output Artifact | Signing Required | CI Workflow |
|----------|-------|-----------------|------------------|-------------|
| **macOS** | [macos.md](macos.md) | `.dmg` (Universal) | Yes (Notarization) | `.github/workflows/macos-build.yml` |
| **Windows** | [windows.md](windows.md) | `.msi`, `.exe` | Optional (Authenticode) | `.github/workflows/windows-build.yml` |
| **Linux** | [linux.md](linux.md) | `.AppImage`, `.deb`, `.rpm` | No | `.github/workflows/linux-build.yml` |
| **iOS** | [ios.md](ios.md) | `.ipa` | Yes (App Store Provisioning) | `.github/workflows/ios-build.yml` |
| **Android** | [android.md](android.md) | `.aab` (App Bundle) | Yes (Keystore) | `.github/workflows/android-build.yml` |

## Quick Start

1. Choose your platform above.
2. Install prerequisites (Xcode, Visual Studio, Flutter SDK, etc.).
3. Run the build command in your platform's guide.
4. Output appears in `desktop/src-tauri/target/...` (Tauri) or `mobile/build/...` (Flutter).

## Local Development

For development builds (debug mode, faster iteration):

- **Desktop:** `pnpm tauri dev` (macOS/Windows/Linux)
- **Mobile:** `flutter run` (iOS/Android on device or emulator)

## CI/CD

Each platform has an automated GitHub Actions workflow. Workflows trigger on:
- New git tags (`v*`)
- Manual dispatch via GitHub Actions UI
- Release branch pushes

See `.github/workflows/` for complete automation details.

---

Verified on: 2026-05-13 — author bench
