# Develop on libnclaw (Rust FFI Library)

By the end of this guide you will:

- Have a working dev loop for editing libnclaw and seeing changes in the Flutter app.
- Understand the Dart-Rust FFI binding pattern and how to add new exports.

## Prerequisites

- Rust stable toolchain (`rustc --version`). Install: [rustup.rs](https://rustup.rs/).
- Cargo target for your platform (added automatically on first build).
- For cross-platform binding generation: `cargo install cbindgen`.
- Flutter 3.x (`flutter --version`) for testing FFI bindings end-to-end.

## What libnclaw is

`libs/libnclaw/` is a Rust crate compiled as `cdylib` + `staticlib`. It is the single source of truth for:

- Shared types (chat messages, threads, personas, tool calls — protocol layer)
- Wire format / serialization (serde-based)
- E2E encryption primitives (X25519 + XChaCha20-Poly1305)
- FFI exports consumed by Dart (`dart:ffi`), Swift (`@_cdecl`), Kotlin (JNI)

Per `.claude/docs/libnclaw-audit.md`, the current state is partial — see that audit for what's implemented vs deferred.

## Steps

### Step 1 — Build for the host

```bash
cd claw/libs/libnclaw
cargo build --release
```

Expected output:

```
Finished `release` profile [optimized] target(s)
```

Artifact location: `target/release/libnclaw.{dylib,so,dll}`.

### Step 2 — Run the test suite

```bash
cargo test
```

Expected: all tests pass. Critical tests cover crypto roundtrip (encrypt → decrypt returns input), tampering detection (flipped bit causes decrypt to fail), and ephemeral keypair generation.

### Step 3 — Lint and format

```bash
cargo clippy -- -D warnings
cargo fmt --check
```

Both must pass before pushing. The CI enforces both.

### Step 4 — Add a new FFI export

Suppose you want to expose a new function `nclaw_summarize` to the client.

In `src/lib.rs` (or a submodule):

```rust
use std::ffi::{c_char, CStr, CString};

#[no_mangle]
pub extern "C" fn nclaw_summarize(input_ptr: *const c_char) -> *mut c_char {
    let input = unsafe { CStr::from_ptr(input_ptr).to_string_lossy().into_owned() };
    let result = format!("Summary: {}", input.chars().take(40).collect::<String>());
    CString::new(result).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn nclaw_free_string(ptr: *mut c_char) {
    if ptr.is_null() { return; }
    unsafe { let _ = CString::from_raw(ptr); }
}
```

Naming convention: `nclaw_<verb>_<noun>` (e.g., `nclaw_encrypt_message`, `nclaw_free_buffer`). Always pair allocation with a free function.

### Step 5 — Generate a C header (optional, for Swift/Kotlin)

Configure cbindgen in `cbindgen.toml`:

```toml
language = "C"
header = "/* Generated — do not edit. */"
include_guard = "NCLAW_H"
```

Run:

```bash
cbindgen --crate libnclaw --output ../../app/macos/Runner/libnclaw.h
```

For Dart, you can use `package:ffigen` or hand-write bindings (see Step 6).

### Step 6 — Add Dart bindings

In `app/lib/services/libnclaw_bindings.dart` (per pattern P-002):

```dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary _lib = _open();

DynamicLibrary _open() {
  if (Platform.isMacOS) return DynamicLibrary.open('libnclaw.dylib');
  if (Platform.isLinux) return DynamicLibrary.open('libnclaw.so');
  if (Platform.isWindows) return DynamicLibrary.open('libnclaw.dll');
  if (Platform.isIOS) return DynamicLibrary.process();
  if (Platform.isAndroid) return DynamicLibrary.open('libnclaw.so');
  throw UnsupportedError('libnclaw not available on this platform');
}

typedef _SummarizeNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _SummarizeDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

final _summarize =
    _lib.lookupFunction<_SummarizeNative, _SummarizeDart>('nclaw_summarize');
final _freeString =
    _lib.lookupFunction<_FreeStringNative, _FreeStringDart>('nclaw_free_string');

String summarize(String input) {
  final inputPtr = input.toNativeUtf8();
  final resultPtr = _summarize(inputPtr);
  final result = resultPtr.toDartString();
  _freeString(resultPtr);
  malloc.free(inputPtr);
  return result;
}
```

Always free Rust-allocated pointers via the matching `nclaw_free_*` extern after use. Always free Dart-allocated pointers via `malloc.free`.

### Step 7 — Test the FFI roundtrip

```bash
cd ../../app
flutter test test/ffi/
```

The test should call `summarize("hello")` via the binding and verify the expected response. If the test fails with `Library not found`, ensure libnclaw is built for the host (Step 1) and present in the search path (or in the app bundle).

### Step 8 — Cross-compile for target platforms

See the per-platform build guides for the exact `rustup target add` and `cargo build` commands:

- iOS: `aarch64-apple-ios`, `aarch64-apple-ios-sim`
- Android: `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android` (via `cargo-ndk`)
- macOS: `aarch64-apple-darwin`, `x86_64-apple-darwin` (combine via `lipo` for universal binary)
- Linux: `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`
- Windows: `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`
- Web: WASM stub (separate compilation; see [[Web-Build-Guide]])

## Verification

After adding a new FFI export:

```bash
# Rust side
cargo test
cargo build --release

# Verify symbol is exported
nm -gU target/release/libnclaw.dylib | grep nclaw_summarize     # macOS
nm -D target/release/libnclaw.so | grep nclaw_summarize          # Linux

# Dart side
cd ../../app && flutter test test/ffi/
```

Symbol must appear in the binary. Dart test must pass.

## Troubleshooting

### "undefined symbol: nclaw_summarize" at runtime

**Symptom:** Dart FFI lookup throws "Failed to lookup symbol".
**Cause:** Function does not have `#[no_mangle] pub extern "C"`, or libnclaw was not rebuilt.
**Fix:** Verify the function signature includes both attributes. Rebuild with `cargo build --release`.

### Dart memory leak after FFI call

**Symptom:** Memory grows over time when calling FFI repeatedly.
**Cause:** Rust-allocated string was not freed via `nclaw_free_string`, or Dart `Pointer<Utf8>` was not freed via `malloc.free`.
**Fix:** Audit each FFI binding to ensure both sides are paired. Pattern P-002 documents the convention.

### "Cargo.toml has incorrect crate-type"

**Symptom:** Other crates can't link libnclaw, or FFI symbols don't appear.
**Cause:** `crate-type` missing `cdylib`.
**Fix:** Verify `Cargo.toml` includes:

```toml
[lib]
crate-type = ["lib", "cdylib", "staticlib"]
```

### Cross-compile fails: "linker not found"

**Symptom:** `cargo build --target ...` fails with linker errors.
**Cause:** No cross-compilation linker installed for the target.
**Fix:**
- Android: install Android NDK and use `cargo-ndk` (`cargo install cargo-ndk`)
- iOS / macOS: use Xcode's bundled toolchain (no extra setup on macOS)
- Windows from Linux/macOS: install `mingw-w64` or use the `cross` crate

## Next Steps

- [[Architecture-Deep-Dive]] — full FFI layer architecture
- [[E2E-Encryption]] — feature page (libnclaw crypto details)
- [[iOS-Build-Guide]] / [[Android-Build-Guide]] / [[macOS-Build-Guide]] — per-platform build details
- [[Troubleshooting]] — common errors across platforms

← [[Home]] | [[Home]] →
