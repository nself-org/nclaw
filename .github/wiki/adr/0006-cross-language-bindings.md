# ADR-0006: Cross-Language Bindings (tauri-specta + flutter_rust_bridge)

**Status:** Accepted 2026-05-11  
**Context:** Desktop and mobile frontends must call Rust core with type safety.  
**Decision:** Desktop uses tauri-specta + ts-rs; mobile uses flutter_rust_bridge.  

## Context

Manual FFI code (C headers, serialization boilerplate, type marshalling) is error-prone and maintenance-heavy. Both platforms need auto-generated bindings from the Rust core.

## Decision

- **Desktop (Tauri ↔ React/TS):** tauri-specta + ts-rs generate TypeScript interfaces from Rust function signatures.
- **Mobile (Flutter ↔ Rust):** flutter_rust_bridge generates Dart bindings from Rust core.

Both binding stacks generate from the same `nclaw-core` crate, ensuring type alignment.

## Rationale

- **Zero manual FFI code:** Generators eliminate boilerplate and keep types in sync automatically.
- **Type safety:** Compile-time errors catch mismatches (wrong argument type, missing field).
- **Single source of truth:** Rust types are authoritative; bindings are derived.

## Consequences

**Positive:**
- Adding a new Rust function auto-generates bindings on both platforms.
- No serialization bugs (type mismatch, missing fields, wrong byte order).

**Negative:**
- Generator configuration is specific to each tool (tauri-specta.toml vs flutter_rust_bridge config).
- Rust signature changes require re-generation.

## Alternatives Considered

- **Manual FFI code:** Full control, but high maintenance burden and easy to get wrong.
- **Protobuf/gRPC:** Language-agnostic, but adds serialization overhead and external dependency.

## References

- tauri-specta: https://github.com/oscartbeaumont/tauri-specta  
- ts-rs: https://github.com/Alec-Deland/ts-rs  
- flutter_rust_bridge: https://cjycode.com/flutter_rust_bridge/
