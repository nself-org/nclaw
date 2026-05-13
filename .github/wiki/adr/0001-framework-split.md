# ADR-0001: Framework Split (Tauri 2 Desktop + Flutter Mobile)

**Status:** Accepted 2026-05-11  
**Context:** ɳClaw v1.1.1 ships desktop and mobile as separate native applications.  
**Decision:** Desktop uses Tauri 2 (React + Vite), mobile uses Flutter. Both compile a shared Rust core.  

## Context

v1.1.0 built all desktop + mobile via Flutter. This unified approach had tradeoffs: Flutter excels at cross-platform mobile (iOS + Android from one codebase) but carries runtime overhead on desktop and limits native OS integration (menu bar, system keychain, file associations).

## Decision

Desktop application compiles to native code via Tauri 2 and React/TypeScript. Mobile application (iOS, Android) builds from Flutter. Both platforms link against the same Rust core (`nclaw-core`) via FFI.

The v1.1.0 Flutter desktop codebase is archived to `legacy-flutter-desktop/` and removed entirely in v1.2.0.

## Rationale

- **Tauri 2 on desktop** provides smaller binaries, native OS APIs (menu bar, dock, notifications, file system), and system keychain integration without runtime overhead.
- **Flutter on mobile** retains proven cross-platform coverage (iOS + Android + web) and strong UI performance on smaller screens.
- **Shared Rust core** eliminates duplicate business logic (sync engine, encryption, LLM integration) and ensures feature parity across platforms.
- **No production v1.1.0 Flutter desktop users** means no migration burden; v1.1.1 ships the archive for reference only.

## Consequences

**Positive:**
- Optimized user experience per platform (native UI patterns, smaller footprint on desktop).
- Type-safe FFI via tauri-specta and flutter_rust_bridge eliminates manual bindings.

**Negative:**
- Two UI codebases (React/TS on desktop, Dart on mobile) require separate development and testing.
- Shared library maintenance (libnclaw Rust crate) is critical; a breaking change cascades to both platforms.

## Alternatives Considered

- **Unified Flutter for all platforms:** Simpler codebase, but bloated desktop app and weaker native OS integration.
- **Unified React Native:** Web + mobile coverage, but Android performance lags Flutter and desktop story is unclear.

## References

- Tauri 2: https://tauri.app/  
- Flutter: https://flutter.dev/  
- libnclaw FFI: `nclaw/core/`
