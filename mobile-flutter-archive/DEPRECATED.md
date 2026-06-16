# DEPRECATED — Flutter Mobile Archive

**Deprecated:** 2026-06-16

**Replaced by:** `nclaw/mobile` — React Native + Expo rewrite (P3-E4-W2-S3)

## Status

This directory contains the archived Flutter mobile implementation of ɳClaw. It is preserved for reference only and is **no longer maintained**.

- No bug fixes will be applied.
- No new features will be added.
- CI/CD pipelines targeting this archive are removed.

## Migration

The React Native + Expo rewrite (`nclaw/mobile`) provides full feature parity with this Flutter implementation:

| Flutter | React Native Equivalent |
|---------|------------------------|
| `lib/` | `src/` |
| `pubspec.yaml` | `package.json` + `app.json` |
| `flutter pub get` | `pnpm install` |
| `flutter build ios` | `eas build --platform ios` |
| `flutter build apk` | `eas build --platform android` |

## Why Replaced

- ASI Policy 2 mandates React Native + Expo for mobile surfaces (Flutter eliminated).
- Dart shares no code with the TypeScript web/backend stack.
- RN allows direct reuse of `@nself/*` shared packages.
- EAS Build provides a managed CI/CD pipeline.

## References

- P3-E4-W2-S3 sprint (RN rewrite)
- ASI frontend-doctrine: `~/Sites/.claude/frontend-doctrine.md`
