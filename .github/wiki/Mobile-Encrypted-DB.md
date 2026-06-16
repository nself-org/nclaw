# Mobile Encrypted Database

ɳClaw mobile stores conversations, drafts, and offline actions in an **AES-256 SQLCipher** database on the device. This document describes the architecture, key management, schema, and how to migrate from the legacy Flutter implementation.

---

## Overview

| Property | Value |
|---|---|
| Engine | SQLite with SQLCipher extension (`@op-engineering/op-sqlite`, `SQLCIPHER=1`) |
| Encryption | AES-256-CBC (SQLCipher default) |
| Key storage | Device Keychain/Keystore via `expo-secure-store` |
| Key format | 32-byte random hex string (64 chars) |
| DB filename | `nclaw.db` |
| Tables | `nclaw_messages`, `nclaw_action_queue`, `nclaw_drafts` |

---

## Key Management

The encryption key is derived on first open and stored in `expo-secure-store` under the key `nclaw_db_key`:

1. `EncryptedDB.open(secureStore)` calls `secureStore.getItem('nclaw_db_key')`.
2. If the key exists, it is passed directly to op-sqlite as the `encryptionKey`.
3. If the key does not exist, a 32-byte cryptographically random key is generated via `crypto.getRandomValues`, stored in SecureStore, then used.
4. If SecureStore access fails at any point, the DB open fails with an error — there is no plaintext fallback.

The key is **never** logged, serialised into source code, or included in error messages.

---

## Schema

### `nclaw_messages`

Cached conversation messages. Persists the on-device copy of each thread so the UI loads instantly without a network round-trip.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID matching server ID |
| `thread_id` | TEXT | FK to conversation thread |
| `role` | TEXT | `user` / `assistant` / `system` |
| `content` | TEXT | Full message text |
| `created_at` | TEXT | UTC ISO 8601 |

### `nclaw_action_queue`

Pending operations queued while the device is offline. Drained on reconnect.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID for deduplication |
| `action_type` | TEXT | Handler discriminator |
| `payload` | TEXT | JSON-serialised payload |
| `status` | TEXT | `pending` / `processing` / `failed` |
| `retry_count` | INTEGER | Incremented on each sync attempt |

### `nclaw_drafts`

One draft per thread. Persists compose-box text so it survives app kill.

| Column | Type | Notes |
|---|---|---|
| `thread_id` | TEXT PK | One draft per thread |
| `content` | TEXT | Current draft text |
| `updated_at` | TEXT | UTC ISO 8601 |

---

## Service API

All operations are in `nclaw/mobile/services/encryptedDB.ts` and exposed via the `useEncryptedDB` React hook.

```ts
const db = useEncryptedDB({ secureStore: new ExpoSecureStore() });

// Wait until ready before performing operations
if (!db.isReady) return;

// Messages
await db.insertMessage({ id, thread_id, role: 'user', content, created_at });
const result = await db.getMessagesByThread(threadId);
await db.deleteMessage(id);

// Action queue
await db.enqueueAction({ id, action_type: 'send_message', payload: JSON.stringify(data) });
const pending = await db.getActions('pending');
await db.updateActionStatus(id, 'processing');
await db.deleteAction(id);

// Drafts
await db.saveDraft({ thread_id, content, updated_at: new Date().toISOString() });
const draft = await db.getDraft(threadId);
await db.deleteDraft(threadId);
```

All methods return `Result<T, AppError>` — no thrown exceptions escape the service.

---

## Migration from Flutter

If the user previously ran the Flutter-based ɳClaw mobile app, the migration service (`nclaw/mobile/services/migrationService.ts`) handles the one-time import:

1. Checks a SecureStore flag (`nclaw_rn_migration_done_v1`). If set, returns immediately (idempotent).
2. Looks up the Flutter DB key under `flutter.nclaw_db_key` (or `nclaw_db_key_flutter` for older builds).
3. Opens the Flutter SQLCipher DB using the Flutter key.
4. Imports rows from Flutter tables (`messages`, `action_queue`, `drafts`) into the RN tables via `INSERT OR IGNORE` (no duplicates).
5. Deletes the Flutter DB file.
6. Sets the migration-done flag.

If the Flutter DB is absent or the key is missing, migration is skipped silently — the app treats this as a fresh install.

Call `migrateFromFlutter` once at app boot, before rendering the main UI:

```ts
import { migrateFromFlutter } from '../services/migrationService';
import { ExpoSecureStore } from '@nself/native-bridge';
import { EncryptedDB } from '../services/encryptedDB';

const secureStore = new ExpoSecureStore();
const dbResult = await EncryptedDB.open(secureStore);
if (dbResult.ok) {
  const migration = await migrateFromFlutter(dbResult.value, secureStore);
  // migration.skipped === true → fresh install or already migrated
}
```

---

## Security Properties

- **Encrypted at rest:** `sqlite3 nclaw.db` returns `SQLITE_NOTADB` — the file is not readable without the SQLCipher key.
- **Key isolation:** The key lives exclusively in the OS Keychain (iOS) / Android Keystore. It is never written to disk in plaintext.
- **Fail-closed:** Any failure in key derivation causes DB open to fail — the app does not fall back to an unencrypted DB.
- **No key in bundle:** The key is not embedded in the JS bundle, not logged, and not included in Sentry payloads.

---

## Build Configuration

`@op-engineering/op-sqlite` must be compiled with the `SQLCIPHER=1` flag. Add this to `app.json` under `expo-build-properties`:

```json
{
  "expo": {
    "plugins": [
      [
        "expo-build-properties",
        {
          "ios": { "extraPodspecArgs": ["OP_SQLITE_USE_SQLCIPHER=1"] },
          "android": { "extraMavenRepos": [] }
        }
      ],
      [
        "@op-engineering/op-sqlite",
        { "sqlcipher": true }
      ]
    ]
  }
}
```

---

## Related

- `nclaw/mobile/services/encryptedDB.ts` — service implementation
- `nclaw/mobile/hooks/useEncryptedDB.ts` — React hook
- `nclaw/mobile/services/migrationService.ts` — Flutter migration
- `@nself/native-bridge` — `SecureStoreInterface` contract
- Ticket: `T-P3-E4-W2-S3-T11`
