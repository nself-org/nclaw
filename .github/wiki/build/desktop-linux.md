# Linux Desktop Build (CI)

The `.github/workflows/desktop-linux.yml` workflow builds ɳClaw desktop for Linux (x64 and arm64) on tag push, producing AppImage, .deb, and .rpm packages.

## What it does

- Triggers on version tags (`v1.1.1`, etc.) and manual dispatch
- Builds in parallel on x64 (`ubuntu-22.04`) and arm64 (`ubuntu-22.04-arm`)
- Installs system dependencies (libwebkit2gtk, libgtk-3, librsvg2, etc.)
- Compiles Tauri 2 desktop app via Rust toolchain for each target
- Bundles as AppImage (portable) + `.deb` (Debian-compatible) + `.rpm` (Red Hat-compatible)
- Uploads artifacts per architecture with 30-day retention

## System dependencies (pre-installed in CI)

- `libwebkit2gtk-4.1-dev` — WebKit rendering engine
- `libgtk-3-dev` — GTK3 UI framework
- `libappindicator3-dev` — System tray / app indicator support
- `librsvg2-dev` — SVG rendering
- `patchelf` — ELF binary patching (for AppImage bundler)
- `libsoup-3.0-dev` — HTTP library

## Artifacts

| Format | File | Use case |
|--------|------|----------|
| **AppImage** | `nClaw-x.y.z-x86_64.AppImage` (or `-aarch64`) | Portable; works on any glibc-compatible Linux; self-contained, no install needed |
| **.deb** | `nclaw_x.y.z_amd64.deb` | Debian / Ubuntu / Pop!_OS / Linux Mint |
| **.rpm** | `nclaw-x.y.z-1.x86_64.rpm` | Fedora / RHEL / openSUSE / Rocky / AlmaLinux |

## Postinst script (future)

The `.deb` package includes `src-tauri/deb/postinst` stub. At v1.2.0, populate with:
- Register desktop file in freedesktop.org registry
- Update icon cache
- Create menu shortcuts

## Troubleshooting

**"libwebkit2gtk-4.1-dev: unable to locate package"**: System deps failed. Check `apt-get update` succeeded.

**Timeout (>25 min)**: Cargo cache miss or slow arm64 build. Subsequent runs reuse cache.

**AppImage: permission denied**: Mark executable: `chmod +x nClaw-*.AppImage`.

**RPM on Red Hat fails**: Some systems require `--nodeps` or additional repos; users may need to `sudo dnf install gtk3`.

See `.github/wiki/build/linux.md` for local development build steps.
