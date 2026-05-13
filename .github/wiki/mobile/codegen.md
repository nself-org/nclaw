# Flutter Rust Bridge Codegen

nClaw mobile uses `flutter_rust_bridge` to generate Dart FFI bindings from the Rust api.rs module in libnclaw.

## Configuration

- **Rust input:** `nclaw/core/src/api.rs` (public bridge surface)
- **Dart output:** `mobile/lib/src/rust/` (generated bindings)
- **Config:** `nclaw/core/flutter_rust_bridge.yaml`

## Regenerating Bindings

After modifying `nclaw/core/src/api.rs`, regenerate bindings:

```bash
cd mobile
make codegen
# or: ./tool/codegen.sh
```

The codegen pipeline:
1. Installs Dart dependencies (`flutter pub get`)
2. Runs `flutter_rust_bridge_codegen generate`
3. Outputs Dart bindings to `lib/src/rust/`
4. Generates C headers for iOS/macOS at `ios/Runner/bridge_generated.h` and `macos/Runner/bridge_generated.h`

## When to Regenerate

- **After adding an FFI function to api.rs**
- **Before committing Rust changes** (bindings must stay in sync)
- **If you see "unresolved reference" errors in Dart**

## Notes

- Codegen requires both Rust and Flutter toolchains installed
- Generated files should be committed to git (allow users to build without Rust)
- Do NOT hand-edit generated files in `lib/src/rust/`
