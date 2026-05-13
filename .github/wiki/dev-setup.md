# nClaw Developer Setup Guide

Get a running nClaw dev build on any of 5 platforms in less than 30 minutes.

## Prerequisites

**Rust:** stable 1.78+ via [rustup](https://rustup.rs/)
```bash
rustup install stable
rustup default stable
```

**Node.js:** v20 LTS or later
```bash
node --version  # verify ≥20
```

**pnpm:** v9.0.0+
```bash
npm install -g pnpm@9
```

**Flutter:** 3.24+ from [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
```bash
flutter --version
```

**Platform-specific:**
- **macOS/iOS:** Xcode 15+. Install CLI tools: `xcode-select --install`
- **Linux:** `libwebkit2gtk-4.1-dev libgtk-3-dev libappindicator3-dev librsvg2-dev patchelf`
  - Ubuntu/Debian: `sudo apt-get install libwebkit2gtk-4.1-dev libgtk-3-dev libappindicator3-dev librsvg2-dev patchelf`
  - Fedora: `sudo dnf install webkit2-gtk3-devel gtk3-devel libappindicator-gtk3-devel librsvg2-devel patchelf`
- **Windows:** WebView2 (auto-installed with Edge), MSVC build tools 2022+
- **Android:** Android Studio Hedgehog+, NDK r26+

## Workspace Structure

```
nclaw/
├── core/           # Rust: libnclaw FFI, sync engine, local LLM
├── desktop/        # Tauri 2 + React + Vite desktop app
├── mobile/         # Flutter desktop + mobile
├── protocol/       # Sync protocol schemas + specs
└── legacy-flutter-desktop/  # archived v1.1.0
```

## Clone & Install

```bash
git clone https://github.com/nself-org/nclaw
cd nclaw

# Install Rust toolchain
rustup toolchain install stable --target wasm32-unknown-unknown

# Tauri CLI
cargo install tauri-cli@^2.0.0

# Install JS deps (desktop)
cd desktop && pnpm install && cd ..

# Install Flutter deps (mobile)
flutter pub get
```

## Run

### Desktop (Tauri 2)
```bash
cd desktop
pnpm tauri dev      # run with hot-reload (~15 min first build)
```

### Mobile
```bash
cd mobile
flutter run         # macOS + iOS: `flutter run -d macos`, iOS: requires provisioning profile
                    # Android: `flutter run -d emulator`
```

### Rust Core Tests
```bash
cd core
cargo test
```

## Code Generation

### Rust → TypeScript bindings (desktop)
```bash
cd core
cargo run --bin export-bindings --features ts-export
# Output: `../desktop/src/lib.ts`
```

### Rust → Dart bindings (mobile)
```bash
cd mobile
flutter pub run build_runner build --delete-conflicting-outputs
```

## Common Pitfalls

1. **`sqlite-vec` fails on Linux?** Install `libsqlite3-dev`:
   ```bash
   sudo apt-get install libsqlite3-dev  # Ubuntu/Debian
   ```

2. **`flutter doctor` warns about iOS deployment?** Run:
   ```bash
   sudo gem install cocoapods
   cd mobile && flutter pub get && cd ..
   ```

3. **Tauri on first build hangs?** Patience—webkit downloads are large. Allow 10–15 min.

4. **llama.cpp metal feature on macOS?** Already enabled in `core/Cargo.toml`. If slow, disable: `cargo build --no-default-features`

5. **Code-generation version mismatch?** Regenerate bindings after pulling:
   ```bash
   cd core && cargo run --bin export-bindings --features ts-export
   cd mobile && flutter pub run build_runner build
   ```

## Next Steps

- **Run desktop dev:** `cd desktop && pnpm tauri dev`
- **Run mobile:** `flutter run` in `mobile/`
- **Read architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Contribute:** See [CONTRIBUTING.md](#)
- **Chat:** [GitHub Discussions](https://github.com/nself-org/nclaw/discussions)
