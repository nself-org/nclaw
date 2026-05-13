# Build ɳClaw for Linux

Build AppImage (portable), deb (Debian), and rpm (Fedora/RHEL) packages.

## Prerequisites

- libwebkit2gtk-4.1-dev, libssl-dev, libappindicator3-dev (Debian/Ubuntu):
  ```bash
  sudo apt-get install libwebkit2gtk-4.1-dev libssl-dev libappindicator3-dev
  ```
- Or (Fedora/RHEL):
  ```bash
  sudo dnf install webkit2gtk4.1-devel openssl-devel libappindicator-gtk3-devel
  ```

## Build Packages

```bash
cd nclaw/desktop
pnpm tauri build --bundles appimage,deb,rpm
```

AppImage is the default for portability (no installation required; works on any Linux distro).

## Output

- **AppImage (portable):** `desktop/src-tauri/target/release/bundle/appimage/ɳClaw_1.1.1_amd64.AppImage`
- **Debian package:** `desktop/src-tauri/target/release/bundle/deb/nclaw_1.1.1_amd64.deb`
- **RPM package:** `desktop/src-tauri/target/release/bundle/rpm/nclaw-1.1.1-1.x86_64.rpm`

Users run AppImage directly (`chmod +x && ./ɳClaw_1.1.1_amd64.AppImage`) or install deb/rpm via package manager.

## Optional: Flatpak

Create `desktop/flatpak/org.nself.nclaw.yml`:

```yaml
app-id: org.nself.nclaw
runtime: org.freedesktop.Platform
runtime-version: '23.08'
sdk: org.freedesktop.Sdk
command: nclaw
```

Build: `flatpak-builder --user --install build org.nself.nclaw.yml`

## Troubleshooting

1. **"libwebkit2gtk-4.1-dev not found"** — Use exact package name per distro (gtk4 vs gtk3). Verify: `dpkg -l | grep webkit`.
2. **"glibc version mismatch (GLIBC_X.YZ not found)"** — AppImage was built on newer glibc. Rebuild on target distro or use compat layer (risky).
3. **"AppImage FUSE error"** — Run with `--appimage-extract-and-run` flag or install libfuse2.
4. **"GTK warnings (no font, missing theme)"** — Non-fatal. Users can suppress via `GTK_DEBUG=0`.
5. **"AppArmor profile denying access"** — Edit `/etc/apparmor.d/` to allow AppImage; distro-dependent.

---

Verified on: 2026-05-13 — author bench
