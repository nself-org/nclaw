# Build ɳClaw for Windows

Build `.msi` (installer) and `.exe` (portable) for Windows 10+.

## Prerequisites

- Windows 10 21H2+
- Visual Studio Build Tools 2022 (C++ workload): https://visualstudio.microsoft.com/downloads/
- WiX Toolset 3.14+: https://github.com/wixtoolset/wix3/releases
- Authenticode code-signing certificate (`.pfx` file) — optional but recommended for SmartScreen reputation

## Build Installers

```bash
cd nclaw/desktop
pnpm tauri build --bundles msi,nsis
```

This generates both MSI (WiX) and NSIS executable installers.

## Code Signing (Optional)

Add your Authenticode cert to `desktop/src-tauri/tauri.conf.json`:

```json
{
  "tauri": {
    "bundle": {
      "windows": {
        "certificateThumbprint": "<thumbprint>",
        "signingIdentity": "<identity>"
      }
    }
  }
}
```

Or sign post-build:

```bash
signtool sign /f cert.pfx /p <password> /t http://timestamp.comodoca.com /fd sha256 \
  desktop/src-tauri/target/release/bundle/msi/ɳClaw_1.1.1_x64_en-US.msi
```

## Output

- **MSI installer:** `desktop/src-tauri/target/release/bundle/msi/ɳClaw_1.1.1_x64_en-US.msi`
- **NSIS installer:** `desktop/src-tauri/target/release/bundle/nsis/ɳClaw_1.1.1_x64-setup.exe`

Users run the installer; optional SmartScreen bypass requires code signing + time (reputation builds after weeks of signatures).

## Troubleshooting

1. **"WebView2 not found"** — Installer attempts automatic download. For offline builds, pre-install: https://aka.ms/webview2/
2. **"WiX not on PATH"** — Add `C:\Program Files (x86)\WiX Toolset v3.14\bin` to system PATH; restart terminal.
3. **"Signtool.exe not found"** — Located in `C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\`. Add to PATH.
4. **"MSVC build tools missing"** — Run Visual Studio Installer → Modify → ensure "Desktop development with C++" is checked.
5. **"Antivirus quarantining .exe"** — Code-signed builds bypass this. For unsigned: add exception or request vendor allowlist.

---

Verified on: 2026-05-13 — author bench
