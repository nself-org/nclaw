# ADR-0007: Credential Vault (Server of Record + OS Keychain)

**Status:** Accepted 2026-05-11  
**Context:** App integrations (email, calendar, APIs) require credential storage. Device loss must not expose credentials.  
**Decision:** Server holds encrypted blobs; each device stores per-device keypair in OS keychain.  

## Context

Users authenticate with third-party services (Gmail, Notion, Slack, etc.). Credentials must be stored securely and survive device loss. A device-specific encryption layer ensures lost device doesn't compromise other devices.

## Decision

- **Server of record:** plugins-pro/vault extension stores encrypted credential blobs.
- **Local mirror:** OS keychain (keyring-rs on desktop, flutter_secure_storage on mobile).
- **Per-device keypair:** Generated on first app install. Private key stays in OS keychain. Public key registered with server.
- **Encryption envelope:** Server encrypts blob with per-user master key, then wraps envelope per-device using the device public key.

Decryption requires both: server blob (can't be stolen without breaking server) + device private key (only on that device).

## Rationale

- **Server is source of truth:** If device is lost, server still has the credential (encrypted; useless without the master key).
- **Per-device keypair:** Limits damage of device compromise; other devices' keys remain safe.
- **OS keychain:** Leverages platform-native secure storage; human cannot accidentally export private keys.

## Consequences

**Positive:**
- Device loss doesn't expose credentials across all devices.
- Revoked device credentials are invalidated server-side without affecting other devices.

**Negative:**
- Requires key management infrastructure (per-device key registration, key rotation policies).
- Complex to explain to users ("why can't I just copy-paste my password?").

## Alternatives Considered

- **Password manager integration (Bitwarden/1Password):** Simpler UX, but adds external dependency.
- **Cleartext local storage:** Unacceptable; any device breach exposes all credentials.

## References

- keyring-rs: https://github.com/hwchen/keyring-rs  
- flutter_secure_storage: https://pub.dev/packages/flutter_secure_storage  
- X25519: https://en.wikipedia.org/wiki/Elliptic_Curve_Diffie%E2%80%93Hellman
