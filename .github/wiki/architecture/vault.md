# nClaw Vault — Architecture & Protocol

## Overview

The nClaw Vault is a **client-side encrypted storage system** for sensitive nClaw data (API keys, oauth tokens, personal credentials). Vault is built on three pillars:

1. **Client keypair generation** — Ed25519 key per device, stored in OS keychain
2. **Envelope encryption** — XChaCha20-Poly1305 AEAD wrapping each secret
3. **Server sync** — devices fetch their encrypted envelopes via Hasura GraphQL

Users never see the keys. The client encrypts all secrets locally, sends the envelope to the server, and later retrieves it by syncing envelopes for the current device.

## Flow: Registration → Sync → Revocation

### 1. Device Registration (T03)

When a user pairs a new device (e.g., a second laptop):

```
Client generates Ed25519 keypair
  ↓
Client sends pubkey + device label to /vault/v1/devices
  ↓
Server stores device record, assigns device_id (UUID)
  ↓
Client stores device_id in OS keychain
```

**Code:** `libnclaw/src/vault/registration.rs`

### 2. Vault Sync (T04)

When the app launches or user requests sync:

```
Client reads device_id from keychain
  ↓
Client calls GET /vault/v1/records?device_id={id}
  ↓
Server returns all envelopes accessible to this device
  ↓
Client decrypts each envelope with its private key
  ↓
Secrets are now available in memory
```

**Code:** `libnclaw/src/vault/sync.rs`

### 3. Device Revocation (T06)

When a user discards an old phone:

```
Client (or another device) calls DELETE /vault/v1/devices/{device_id}
  ↓
Server marks device revoked, cascades wipe all its envelopes
  ↓
Other devices receive sync notification, re-fetch clean state
```

**Code:** `libnclaw/src/vault/revocation.rs`

## Rotation Policy (T07)

Each device's envelopes have a rotation cadence:

| Cadence | Interval |
|---------|----------|
| Manual | never (user-initiated) |
| Daily | 24h |
| Weekly | 7d |
| Monthly | 30d |

**Code:** `libnclaw/src/vault/rotation.rs`

At rotation time, the client re-encrypts all envelopes with the same device keypair (or regenerates keypair if desired) and uploads fresh envelopes to the server.

## Telemetry (T08)

Four counters track vault health:

- `envelopes_sealed` — successful encryptions
- `envelopes_opened` — successful decryptions
- `devices_registered` — new devices paired
- `devices_revoked` — devices removed

**Code:** `libnclaw/src/vault/telemetry.rs`

## Server Schema (Hasura)

```graphql
type Device {
  id: UUID!
  user_id: UUID!
  pubkey: Base64String!
  label: String
  platform: String
  created_at: DateTime!
  revoked_at: DateTime
}

type VaultRecord {
  id: UUID!
  user_id: UUID!
  device_id: UUID!
  ciphertext: Base64String!
  nonce: Base64String!
  created_at: DateTime!
}
```

RLS ensures users see only their own devices and records.

## Crypto Details

- **Key exchange:** Ed25519 signing + X25519 static secrets
- **Encryption:** XChaCha20-Poly1305 (256-bit XChaCha20, 128-bit Poly1305 AEAD)
- **Nonce:** 24-byte random per envelope (included in ciphertext)
- **Key derivation:** blake2b(device_private_key + record_id) for per-record keys

## Future Enhancements

- **Threshold crypto:** Multi-device recovery — 2-of-3 devices needed to decrypt master secret
- **Backup codes:** Human-readable recovery codes stored on paper
- **Hardware keys:** YubiKey / TouchID / FaceID for additional auth factor
