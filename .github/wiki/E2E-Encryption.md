# E2E Encryption

**Status:** Active in libnclaw (Rust). Flutter integration is in progress per `.claude/docs/FEATURES.md`.

## Overview

End-to-end encryption protects message content and memory from the server operator. With E2E enabled, the backend stores ciphertext only — even an attacker with full database access cannot read the plaintext.

ɳClaw uses X25519 Diffie-Hellman key exchange and XChaCha20-Poly1305 authenticated encryption. The cipher suite is locked. Implementation lives in `libs/libnclaw/` (Rust) and is exposed to clients via FFI.

Each device generates its own keypair on first launch. Keys are stored in the platform keychain (iOS Keychain, Android Keystore, macOS Keychain, libsecret on Linux). There is no password-based key derivation and no recovery — by design. Lose the device key, lose access to that device's encrypted memory.

## Requirements

| Item | Required | Notes |
|------|----------|-------|
| ɳSelf CLI | 1.0+ | F01-MASTER-VERSIONS |
| libnclaw | per `.claude/docs/libnclaw-audit.md` | Built for the host platform |
| Plugin: `claw` | Yes | Stores encrypted blobs |
| Plugin: `ai` | Yes | Generates responses (sees plaintext server-side; encrypted before storage) |
| Service: PostgreSQL | Yes | F08-SERVICE-INVENTORY |
| Platform keychain | Yes | iOS Keychain, Android Keystore, macOS Keychain, libsecret on Linux |
| Tier | Pro ($1.99/mo) | per F07-PRICING-TIERS |
| Bundle | ɳClaw Bundle ($0.99/mo) | per F06-BUNDLE-INVENTORY |

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `CLAW_E2E_ENABLED` | `false` | Master switch — enable E2E for this account |
| `CLAW_E2E_KEY_ROTATION_DAYS` | `0` (never) | Auto-rotate device key every N days; 0 = never |

E2E is a per-account setting, configured in Settings > Privacy.

## Usage

### Enabling E2E

Settings > Privacy > End-to-End Encryption > Enable.

The app generates a `DeviceKeypair` (X25519) on first enable, stores it in the platform keychain, and registers the public key with the backend. From this point, new messages and memory entries are encrypted on-device before being sent.

### Pairing a second device

Settings > Privacy > Pair new device. The current device displays a QR code (or a 6-digit short code). On the new device, scan the QR (or enter the short code) during onboarding. The current device sends an encrypted bootstrap to the new device containing the shared session keys.

### Sending an encrypted message

Once E2E is on, every message is automatically encrypted. The `claw` plugin stores ciphertext in `np_claw_messages` (the `encrypted_content` column). The plaintext never lives at rest on the server.

### Reading on a different device

A device that has been paired (Settings > Privacy > Pair) can decrypt all messages and memory written by other paired devices. A non-paired device sees ciphertext only — even with valid login credentials.

### Recovering after device loss

There is no recovery. By design.

If you lose your only paired device, the encrypted memory is unrecoverable. To mitigate: pair multiple devices, or accept that some categories of memory should not be E2E (toggle E2E off for those).

## Threat model

| Threat | E2E protects? |
|--------|---------------|
| Compromised account password | Yes — attacker without device key sees ciphertext |
| Compromised server operator | Yes — operator sees ciphertext only at rest |
| Compromised device | No — device's plaintext is decryptable on that device |
| Server compromised mid-conversation | Partial — in-flight requests to AI provider go through plaintext server-side; only at-rest storage is ciphertext |
| Lost device | No backup — see Recovery section |

What the server CAN see (E2E enabled):
- Timestamps
- Topic IDs (not topic names if you re-encrypt those — currently topic names are not E2E)
- User identity
- Number of messages

What the server CANNOT see:
- Message content
- Memory entry content (facts, decisions, entities)
- Persona system prompts (when stored encrypted)

## Limitations

- AI inference cannot happen with E2E content directly. The user's device decrypts, sends plaintext to the AI provider via the `ai` plugin, receives the plaintext response, then re-encrypts before storage. The "in-flight" plaintext is visible to the backend during inference.
- Server-side semantic search (pgvector) cannot operate on ciphertext. With E2E on, search falls back to client-side index of decrypted content.
- Web build cannot use libnclaw FFI. Web E2E uses a WASM stub if compiled, or falls back to non-E2E. See [[Web-Build-Guide]].
- Key rotation is manual. There is no automated re-encryption flow yet.
- Tool calls (file access, shell, browser) are not E2E. Tool args and results pass through the backend in plaintext.

### Known issues

None currently tracked.

## Troubleshooting

### Cannot decrypt messages on a paired device

**Symptom:** New paired device shows ciphertext placeholders instead of message content.
**Cause:** Pairing did not transfer session keys correctly, or session keys have rotated.
**Fix:** Re-pair the device via Settings > Privacy > Pair new device. The current device's keys are sent again.

### "E2E not available on this platform"

**Symptom:** Web app shows E2E option as disabled.
**Cause:** Web cannot use libnclaw FFI. WASM stub may not be configured.
**Fix:** Use the Flutter desktop / mobile builds for E2E. On web, accept non-E2E or configure the WASM stub per [[Web-Build-Guide]].

### Lost access to memory after device loss

**Symptom:** Lost the only paired device. New device cannot decrypt history.
**Cause:** No recovery — by design. The device key is gone.
**Fix:** Disable E2E (new device, fresh key). Future messages will be encrypted with the new key, but old encrypted memory is unrecoverable.

### Performance degradation on long messages

**Symptom:** Decryption is noticeably slow on long messages.
**Cause:** libnclaw FFI is being called on the UI isolate.
**Fix:** Per pattern P-010, FFI crypto should run on a background isolate. File a bug if it isn't.

## Related

- [[Memory]] — what gets encrypted (chat content, facts, decisions, entities)
- [[Architecture-Deep-Dive]] — full crypto data flow
- [[libnclaw-Dev-Guide]] — work on the FFI library
- [[Web-Build-Guide]] — web E2E options
- [[Features]] — full feature index

← [[Features]] | [[Home]] →
