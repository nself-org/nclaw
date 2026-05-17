# nclaw/mobile/

Flutter mobile codebase (iOS + Android). Carries forward from v1.1.0 `app/`.

## CI Status

| Platform | Status |
|---|---|
| iOS | [![iOS CI](https://github.com/nself-org/nclaw/actions/workflows/mobile-ios.yml/badge.svg)](https://github.com/nself-org/nclaw/actions/workflows/mobile-ios.yml) |
| Android | [![Android CI](https://github.com/nself-org/nclaw/actions/workflows/mobile-android.yml/badge.svg)](https://github.com/nself-org/nclaw/actions/workflows/mobile-android.yml) |
| macOS | [![macOS CI](https://github.com/nself-org/nclaw/actions/workflows/mobile-macos.yml/badge.svg)](https://github.com/nself-org/nclaw/actions/workflows/mobile-macos.yml) |
| Linux | [![Linux CI](https://github.com/nself-org/nclaw/actions/workflows/mobile-linux.yml/badge.svg)](https://github.com/nself-org/nclaw/actions/workflows/mobile-linux.yml) |
| Windows | [![Windows CI](https://github.com/nself-org/nclaw/actions/workflows/mobile-windows.yml/badge.svg)](https://github.com/nself-org/nclaw/actions/workflows/mobile-windows.yml) |
| FRB Drift | [![FRB Codegen Check](https://github.com/nself-org/nclaw/actions/workflows/frb-codegen-check.yml/badge.svg)](https://github.com/nself-org/nclaw/actions/workflows/frb-codegen-check.yml) |

Per [architecture-decisions.md](../.claude/phases/current/p101-storm/architecture-decisions.md) Decision #1, mobile is Flutter-only. Desktop has moved to Tauri 2 in `../desktop/`. Desktop targets (`linux/`, `macos/`) inside this Flutter tree are residual from v1.1.0 and are archived alongside `../legacy-flutter-desktop/` in v1.2.0.

## Build

```bash
cd mobile
flutter pub get
flutter build ios --release
flutter build appbundle --release   # Android
```

## Bridge to core/

Subsequent S12 tickets wire `flutter_rust_bridge` against `../core/` (the shared Rust crate). v1.1.1 includes the scaffolding; full bridge codegen lands in S14.

## Layout

Standard Flutter app layout (`lib/`, `android/`, `ios/`, `pubspec.yaml`, etc.). See `lib/` for the Riverpod state, GraphQL clients, and onboarding flows.

## What changed

- v1.1.0: lived at `nclaw/app/`.
- v1.1.1: renamed to `nclaw/mobile/` (P101 S12.T02 monorepo restructure).
