# nclaw/core/

Shared Rust crate consumed by `desktop/` (Tauri) and `mobile/` (Flutter via flutter_rust_bridge) per [architecture-decisions.md](../.claude/phases/current/p101-storm/architecture-decisions.md) Decision #2.

## Contents

- Shared types (state, events, sync envelopes, vault entries)
- Protocol definitions (wire format with server, ack/replay semantics)
- E2E encryption: X25519 key exchange + ChaCha20-Poly1305 AEAD
- FFI surface for cross-platform consumption (iOS .framework, Android .so, Tauri native module, WASM stub for web)

## Crate naming

Package name is `libnclaw` (historical). Decision #2 nominates `nclaw-core` as the future name; rename is tracked as a follow-up ticket — leaving the package name unchanged here keeps the existing FFI consumer paths working through v1.1.1.

## Build

```bash
cd ../  # repo root
cargo build -p libnclaw
cargo test -p libnclaw
```

## Layout

```text
core/
├── Cargo.toml
├── cbindgen.toml         — C header generation
└── src/
    ├── lib.rs            — crate root
    ├── types.rs          — shared data types
    ├── protocol.rs       — wire protocol
    ├── crypto.rs         — X25519 + ChaCha20-Poly1305
    └── plugin.rs         — plugin protocol scaffolding
```

## Cross-platform consumption

| Target | Mechanism |
| --- | --- |
| Desktop (Tauri) | direct dependency (`../desktop/src-tauri/Cargo.toml`) |
| Mobile (Flutter) | flutter_rust_bridge codegen → Dart bindings |
| iOS / Android (native) | C ABI via cbindgen + cargo-mobile |
| Web | WASM stub or REST proxy fallback (no native FFI on web) |
