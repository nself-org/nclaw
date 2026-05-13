# Legacy Flutter Desktop — v1.1.0

**Status:** Frozen as of 2026-05-11. Read-only historical reference. Will be removed in v1.2.0.

This directory contains the v1.1.0 Flutter desktop client for ɳClaw. v1.1.1 replaces it with Tauri 2 for better native performance and ecosystem support.

## Why Archived

- Flutter desktop is maintained separately in the Dart ecosystem
- Tauri 2 + React delivers better macOS, Linux, and Windows UX
- Smaller binary footprint and faster cold start

## Build Instructions (Historical)

If you need to rebuild the v1.1.0 Flutter desktop client:

```bash
cd legacy-flutter-desktop
flutter pub get
flutter build macos --release    # macOS
flutter build linux --release    # Linux
flutter build windows --release  # Windows
```

Requires Flutter 3.x and platform-specific SDKs (Xcode, LLVM, Visual Studio).

## Migration Path

v1.1.1 and later use Tauri 2. See [migration guide](../.github/wiki/migration/v1.1.0-to-v1.1.1.md).
