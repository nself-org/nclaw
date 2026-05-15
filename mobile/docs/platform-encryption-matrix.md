# Platform At-Rest Encryption Matrix

**Scope:** `nclaw/mobile` Flutter application (the cross-platform mobile + macOS-desktop client). Updated for v1.1.2.

This document is the authoritative answer to "is the local nClaw database encrypted at rest on platform X?"

## The matrix

| Platform | SQLCipher backend | Passphrase storage | At-rest encryption | Notes |
|---|---|---|---|---|
| iOS | sqflite_sqlcipher | iOS Keychain (first_unlock) via flutter_secure_storage | Yes | Production target |
| Android | sqflite_sqlcipher | Keystore-backed EncryptedSharedPreferences via flutter_secure_storage | Yes | Production target |
| macOS | sqflite_sqlcipher | macOS Keychain via flutter_secure_storage | Yes | Production target for the Flutter macOS build |
| Linux | not supported | — | No (database open fails) | Not a Flutter mobile target. Use the Tauri 2 desktop client (`nclaw/desktop`) on Linux. |
| Windows | not supported | — | No (database open fails) | Not a Flutter mobile target. Use the Tauri 2 desktop client (`nclaw/desktop`) on Windows. |
| Web | not supported | — | No (database open fails) | Web build is a stub for preview-only flows; persistent storage is not available. |

## Behavior on unsupported platforms

`EncryptedDbService.open(...)` throws `UnsupportedError` on Linux, Windows, and web. There is no silent fallback to plaintext sqflite. Production code paths must not catch and downgrade this error — the correct action is to disable any feature that requires a local database on those platforms or route to the Tauri 2 desktop client (Linux / Windows).

## Why no Linux / Windows SQLCipher in v1.1.x

`sqflite_sqlcipher` does not ship Linux or Windows native binaries. Adding SQLCipher there would require either:

1. `sqflite_common_ffi` + a bundled SQLCipher build of `libsqlcipher` for both platforms, or
2. Switching to a Rust SQLCipher binding via FFI (matching the Tauri 2 desktop path).

Both are larger changes than the v1.1.2 patch window allows. The Flutter target for v1.1.x is mobile + macOS only. The Tauri 2 desktop client (`nclaw/desktop`) handles Linux and Windows and has its own at-rest encryption story documented in `nclaw/desktop/docs/`.

## Release-note alignment

v1.1.1 release notes have been corrected to scope the at-rest encryption claim to iOS, Android, and macOS only. Earlier wording that implied ecosystem-wide at-rest encryption was inaccurate and is superseded.

## Testing

Unit tests that need a database handle on an unsupported platform must construct an in-memory plain sqflite handle directly inside the test harness with an explicit comment that production code never takes this path. Do not invoke `EncryptedDbService.open` from a test that runs on Linux or Windows CI runners — it will throw.

## See also

- `nclaw/mobile/lib/services/encrypted_db_service.dart` — implementation
- `nclaw/.github/wiki/E2E-Encryption.md` — end-to-end encryption layer (separate concern, applies across all platforms for in-transit + server-at-rest of message content)
- `nclaw/desktop/docs/` — Tauri 2 desktop client encryption story
