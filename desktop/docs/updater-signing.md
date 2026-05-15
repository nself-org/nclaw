# Tauri Updater Signing — nClaw Desktop

## Overview

The Tauri 2 updater plugin verifies update bundles using minisign signatures.
The public key is embedded in `src-tauri/tauri.conf.json` (committed, safe).
The private key is held offline and used only when signing release artifacts.

## Key Locations

| Item | Path | Perms | Tracked? |
| --- | --- | --- | --- |
| Public key file | `~/.config/nself/tauri-updater.pub` | 0644 | No (developer local) |
| Private key file | `~/.config/nself/tauri-updater.key` | 0600 | No (NEVER commit) |
| Embedded pubkey (Tauri format) | `src-tauri/tauri.conf.json` → `plugins.updater.pubkey` | n/a | Yes (public key only) |
| Vault entries | `~/.claude/vault.env` → `TAURI_UPDATER_*` | 0600 | No |
| Key ID | `80B1E1EBA42A2645` | n/a | Reference only |

## Vault Variables

```bash
TAURI_UPDATER_PUBLIC_KEY        # base64 of full .pub file (Tauri format)
TAURI_UPDATER_PRIVATE_KEY_PATH  # absolute path to private key (NEVER bytes)
TAURI_UPDATER_KEY_ID            # short hex ID for cross-reference
```

## Signing a Release Artifact

```bash
source ~/.claude/vault.env
minisign -S -s "$TAURI_UPDATER_PRIVATE_KEY_PATH" \
  -m path/to/nclaw-desktop-{version}-{target}.{ext}
# Produces path/to/...{ext}.minisig — upload alongside the artifact.
```

The Tauri updater downloads `latest-{{target}}.json` from the endpoint
configured in `tauri.conf.json` (`https://packages.nself.org/desktop/latest-{{target}}.json`).
That manifest references the artifact URL plus its `.minisig` signature.
On launch the updater downloads both, verifies the signature against the
embedded public key, and applies the update only if verification passes.

## Verification (manual)

```bash
minisign -Vm path/to/artifact -p ~/.config/nself/tauri-updater.pub
```

## Rotation Procedure

Rotate the keypair only on suspected compromise or scheduled 24-month cadence.
A rotation requires a coordinated client upgrade because the public key is
embedded in shipped binaries.

1. Generate a new keypair offline:
   ```bash
   minisign -G -p ~/.config/nself/tauri-updater.pub.new \
                -s ~/.config/nself/tauri-updater.key.new -W
   chmod 0600 ~/.config/nself/tauri-updater.key.new
   ```
2. Base64-encode the new public key file:
   ```bash
   base64 -i ~/.config/nself/tauri-updater.pub.new | tr -d '\n'
   ```
3. Ship a bridge release containing BOTH keys (Tauri updater supports an array
   of `pubkey` values — verify against any). Sign the bridge release with the
   OLD key so existing installs accept it.
4. After 90 days (or sufficient install penetration), ship a follow-up release
   removing the old key. Sign with the NEW key.
5. Archive the old private key to encrypted cold storage. Update vault
   variables to reference the new key path.
6. Update this document with the new key ID and rotation date.

## Backup

The private key file is the ONLY signing material. Loss = inability to ship
updates. Back it up to:

- 1Password vault (encrypted at rest)
- Encrypted USB drive in physical safe
- `age`-encrypted copy in succession runbook

Never store the private key in:
- Git (any repo)
- Cloud storage without client-side encryption
- Slack / email / chat
- CI environment variables (use signing-only ephemeral runners with short-lived
  access if CI signing is ever introduced; current process is offline-only).

## History

| Date | Event | Key ID |
| --- | --- | --- |
| 2026-05-15 | Initial keypair generated; placeholder retired (P102 W14 V13-S1 fix) | 80B1E1EBA42A2645 |

## See Also

- `src-tauri/tauri.conf.json` — embedded public key
- W8-T1 sprint deliverable — Tauri updater plugin integration
- P102 Wave 14 V13-S1 — original SIEGE finding (placeholder pubkey)
