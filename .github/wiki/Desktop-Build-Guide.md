# Build ɳClaw for Desktop (Linux + Windows)

By the end of this guide you will:

- Have ɳClaw running as a Tauri desktop app on Linux or Windows.
- Have packaged installers (deb / rpm / AppImage on Linux; MSIX / installer on Windows).

## Prerequisites

- Rust stable toolchain (`rustc --version`).
- Node 18+ and pnpm 8+ (`pnpm --version`). Tauri uses pnpm for its frontend assets.
- Tauri CLI: `cargo install tauri-cli`.
- Linux: build-essential, libwebkit2gtk-4.1-dev, libssl-dev, libgtk-3-dev, libayatana-appindicator3-dev. Install via `apt`/`dnf`/`pacman`.
- Windows: WebView2 runtime (preinstalled on Windows 11; install via Microsoft for Windows 10).
- Optional: `flutter_distributor` for additional packaging formats: `dart pub global activate flutter_distributor`.

## Steps

### Step 1 — Set up the desktop UI

The Tauri desktop app lives in `apps/desktop/`. Install dependencies:

```bash
cd claw/apps/desktop
pnpm install
```

### Step 2 — Cross-compile libnclaw for the target

For Linux (current host architecture):

```bash
cd ../../libs/libnclaw
cargo build --release
```

For Windows from a Linux/macOS host (cross-compile):

```bash
rustup target add x86_64-pc-windows-msvc
cargo build --release --target x86_64-pc-windows-msvc
```

Native Windows build:

```bash
cargo build --release
```

### Step 3 — Build the Tauri desktop app

For development:

```bash
cd ../../apps/desktop
cargo tauri dev
```

This launches a hot-reloading development build.

For release on Linux:

```bash
cargo tauri build
```

Expected output (artifacts under `apps/desktop/src-tauri/target/release/bundle/`):

```
deb/nclaw_1.1.1_amd64.deb
rpm/nclaw-1.1.1-1.x86_64.rpm
appimage/nclaw_1.1.1_amd64.AppImage
```

For release on Windows:

```bash
cargo tauri build
```

Output:

```
msi/nclaw_1.1.1_x64_en-US.msi
nsis/nclaw_1.1.1_x64-setup.exe
```

For MSIX on Windows (alternative):

```bash
cargo tauri build --bundles msix
```

### Step 4 — Configure system tray and native menu

Edit `apps/desktop/src-tauri/tauri.conf.json` to enable the system tray icon and native menu items. ɳClaw ships with:

- Tray icon with quick actions: New chat, Open ɳClaw, Quit
- Native menu: File, Edit, View, Window, Help (platform-appropriate per OS)

Verify the icons exist at `apps/desktop/src-tauri/icons/` (16x16, 32x32, 64x64, 128x128, 256x256, 512x512 per platform conventions).

### Step 5 — Configure the Tauri auto-updater

In `tauri.conf.json` enable the updater:

```json
"updater": {
  "active": true,
  "endpoints": ["https://updates.nself.org/claw/{{target}}/{{current_version}}"],
  "dialog": true,
  "pubkey": "<your-public-key>"
}
```

Generate signing keys:

```bash
cargo tauri signer generate
```

Sign each release artifact and publish the signature alongside the installer. The auto-updater verifies signatures before installing.

### Step 6 — Helper scripts

The repo includes packaging helpers under `scripts/`:

```bash
./scripts/build-deb.sh      # Linux deb only
./scripts/build-rpm.sh      # Linux rpm only
./scripts/build-appimage.sh # Linux AppImage only
```

Use these when you only need one format. `cargo tauri build` produces all three by default on Linux.

## Verification

### Linux

```bash
sudo dpkg -i apps/desktop/src-tauri/target/release/bundle/deb/nclaw_*.deb
nclaw
```

The app should launch. Check the system tray for the ɳClaw icon.

For AppImage (no install needed):

```bash
chmod +x apps/desktop/src-tauri/target/release/bundle/appimage/nclaw_*.AppImage
./apps/desktop/src-tauri/target/release/bundle/appimage/nclaw_*.AppImage
```

### Windows

Run the `.msi` or `.exe` installer. Check Start Menu for ɳClaw. Launch and verify the system tray icon appears.

For MSIX: install via `Add-AppxPackage` in PowerShell:

```powershell
Add-AppxPackage -Path "nclaw_1.1.1_x64.msix"
```

## Troubleshooting

### Linux: "libwebkit2gtk-4.1.so.0: cannot open shared object file"

**Symptom:** App crashes on launch with a missing webkit2gtk library.
**Cause:** webkit2gtk is not installed on the user's system.
**Fix:** Install via the user's package manager:
- Debian/Ubuntu: `sudo apt install libwebkit2gtk-4.1-0`
- Fedora: `sudo dnf install webkit2gtk4.1`
- Arch: `sudo pacman -S webkit2gtk`

The deb / rpm packages should declare this as a dependency.

### Windows: "WebView2 not found"

**Symptom:** Installer prompts to install WebView2, or app crashes on launch.
**Cause:** Windows 10 does not preinstall WebView2.
**Fix:** Bundle the WebView2 fixed runtime in the installer. In `tauri.conf.json` set `"windows": { "webviewInstallMode": { "type": "embedBootstrapper" } }`.

### MSIX install fails with "package signature does not match"

**Symptom:** Windows refuses to install the MSIX.
**Cause:** Self-signed cert is not trusted by the user's machine.
**Fix:** Use a code-signing certificate from a CA. For testing: install the self-signed cert into Trusted Root Certification Authorities on the test machine.

### libnclaw not found at runtime

**Symptom:** App launches but crashes with "library libnclaw not found".
**Cause:** The native library was not bundled with the Tauri app.
**Fix:** In `tauri.conf.json` add the libnclaw artifact to `bundle.resources`. Verify it's copied to the bundle output.

## Next Steps

- [[macOS-Build-Guide]] — build for macOS
- [[libnclaw-Dev-Guide]] — work on the Rust FFI library
- [[Architecture-Deep-Dive]] — system architecture
- [[Troubleshooting]] — common errors across platforms

← [[Home]] | [[Home]] →
