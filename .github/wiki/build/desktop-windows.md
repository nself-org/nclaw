# Windows Desktop Build (CI)

The `.github/workflows/desktop-windows.yml` workflow builds ɳClaw desktop for Windows (x64) on tag push.

## What it does

- Triggers on version tags (`v1.1.1`, etc.) and manual dispatch
- Runs on `windows-2022` with 20-minute timeout
- Installs Rust toolchain, Tauri CLI, and pnpm dependencies
- Compiles Tauri 2 desktop app for x86_64-pc-windows-msvc
- **Unsigned at v1.1.1** — EV certificate signing wired in T06 once cert lands
- Uploads `.msi` and `.exe` installers as CI artifacts (30-day retention)

## Secrets required (v1.1.1)

None currently. At T06 when EV cert is acquired:

| Secret | Value |
|--------|-------|
| `WINDOWS_EV_CERT_THUMBPRINT` | SHA-1 thumbprint of EV code signing certificate |

Add to GitHub → Settings → Secrets and variables → Actions. Once set, signtool will auto-sign all MSI and executable files.

## Signing (future — T06)

When `WINDOWS_EV_CERT_THUMBPRINT` is configured, the workflow will:
1. Locate all `.msi` and `.exe` files in the build bundle
2. Sign each with `signtool` using the EV cert
3. Timestamp with DigiCert's TSA (RFC 3161 compliant)

Artifacts become **signed and timestamped**, enabling SmartScreen and Windows Update distribution without warnings.

## Troubleshooting

**"No such file or directory: target/..."**: Cargo build failed silently. Check the build log for Rust / Node / pnpm errors.

**Timeout (>20 min)**: Cargo cache miss (first build). Subsequent runs reuse the cache.

**Signtool fails at T06**: Verify cert thumbprint is correct in GitHub secrets.

See `.github/wiki/build/windows.md` for local development build steps.
