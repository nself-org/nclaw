# Mobile Offline-First Sync — ɳClaw

**Ticket:** S37-T08  
**Applies to:** `app/` (Flutter — iOS, Android, macOS)

---

## Architecture Overview

ɳClaw mobile is offline-first: the app reads from a local SQLite cache at all times and writes user mutations to a local write queue. Network activity happens in the background and is never on the hot path for UI rendering.

Three services coordinate to keep local and server state in sync:

| Service | File | Role |
|---|---|---|
| `OfflineCacheService` | `app/lib/services/offline_cache_service.dart` | SQLite read/write for all cached data + write queue |
| `BackgroundSyncService` | `app/lib/services/background_sync_service.dart` | Periodic 15-minute sync via Workmanager |
| `ConnectivitySyncService` | `app/lib/services/connectivity_sync_service.dart` | Reconnect-triggered immediate flush |

`EncryptedDbService` (`app/lib/services/encrypted_db_service.dart`) sits below all three as the SQLite-opening layer and handles the SQLCipher vs plain-sqflite decision transparently.

```
UI reads ─────────────────────────────→ OfflineCacheService (SQLite)
UI writes (offline) → write_queue ────→ OfflineCacheService (SQLite)
                                                 ↑ flush
                        BackgroundSyncService ──┘ (every 15 min, network required)
                        ConnectivitySyncService ─┘ (on reconnect, 3s debounce)
                                                 ↓ pull
                               Server (nSelf backend + claw plugin)
```

---

## Write Queue Pattern

When the device is offline (or any network call fails mid-flight), user mutations are persisted to the `write_queue` table rather than being dropped. This makes writes durable across app restarts.

### Enqueue

```dart
await OfflineCacheService.instance.enqueueWrite(
  endpoint: '/claw/memory',
  method: 'POST',
  body: jsonEncode(payload),
);
```

Each row records: `endpoint`, `method`, `body` (nullable for DELETE), `created_at`, and `status` (default `pending`).

### Flush

`BackgroundSyncService._flushWriteQueue` iterates all `pending` rows ordered by `created_at ASC` (FIFO). For each:

1. Constructs the HTTP request from the stored method + endpoint + body.
2. On HTTP 2xx: calls `markWriteComplete(id)`.
3. On HTTP 4xx/5xx: calls `markWriteFailed(id)`.
4. On network error (exception): leaves the row as `pending` so the next sync cycle retries it.

`markWriteFailed` does not delete the row — it flags it for inspection. Callers can query `status = 'failed'` to surface error states to the user or retry logic.

`pendingWriteCount()` returns the number of outstanding writes and can drive a UI indicator (e.g. "3 changes waiting to sync").

---

## Cache Tables

All tables are in `nclaw_cache.db`. Schema is created at v1 in `OfflineCacheService._initDb`.

### `conversations`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Server-assigned UUID |
| `data` | TEXT | Full conversation JSON, serialized via `jsonEncode` |
| `updated_at` | TEXT | ISO-8601 timestamp set on every upsert |

Upserts use `ConflictAlgorithm.replace` — server data always replaces what is cached.  
Read back: `getCachedConversations()` returns decoded maps ordered by `updated_at DESC`.

### `messages`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Server-assigned UUID |
| `conversation_id` | TEXT | FK reference (not enforced in SQLite) |
| `data` | TEXT | Full message JSON |
| `created_at` | TEXT | ISO-8601 timestamp set on every upsert |

Read back: `getCachedMessages(conversationId)` returns decoded maps ordered by `created_at ASC` (chronological).

### `topics`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Server-assigned UUID |
| `data` | TEXT | Full topic JSON |
| `updated_at` | TEXT | ISO-8601 timestamp set on every upsert |

Bulk-written via `db.batch()` in `cacheTopics`. Read back with `getCachedTopics()`.

### `memories`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Server-assigned UUID |
| `entity_type` | TEXT | e.g. `fact`, `person`, `preference`; defaults to `fact` |
| `data` | TEXT | Full memory JSON |
| `updated_at` | TEXT | ISO-8601 timestamp set on every upsert |

Bulk-written via `db.batch()` in `cacheMemories`. Read back with `getCachedMemories({entityType})` — pass `entityType` to filter, omit for all rows.

### `write_queue`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | Local surrogate key |
| `endpoint` | TEXT | Server-relative path, e.g. `/claw/memory` |
| `method` | TEXT | `POST`, `PATCH`, `PUT`, or `DELETE` |
| `body` | TEXT nullable | JSON body; null for DELETE |
| `created_at` | TEXT | ISO-8601 enqueue time |
| `status` | TEXT | `pending` / `complete` / `failed` |

---

## Sync Triggers

Two independent triggers call `BackgroundSyncService.execute(serverUrl)`:

### 1. Periodic background task (15 minutes)

Registered by `BackgroundSyncService.register()`, called once at app startup:

```dart
await Workmanager().registerPeriodicTask(
  taskName,
  taskName,
  frequency: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingWorkPolicy.replace,
  backoffPolicy: BackoffPolicy.exponential,
);
```

Key constraints:
- `networkType: NetworkType.connected` — Workmanager will not schedule the task when there is no network, preventing unnecessary wakeups.
- `ExistingWorkPolicy.replace` — re-registering on app launch cancels any stale queued task and starts fresh.
- `BackoffPolicy.exponential` — if the task fails (e.g. server unreachable), the OS retries with exponential back-off rather than hammering the server.

The callback is a top-level function (`callbackDispatcher`) marked `@pragma('vm:entry-point')` so the Dart runtime keeps it alive in the background isolate.

### 2. Reconnect-triggered sync

`ConnectivitySyncService.start(resolveServerUrl)` subscribes to `connectivity_plus` change events. When it detects an offline-to-online transition:

1. Cancels any pending debounce timer.
2. Waits 3 seconds (absorbs flaky cellular toggling).
3. Calls `resolveServerUrl()` — a lambda that reads the currently active server from the connection provider at the time of firing, not at subscription time.
4. Calls `BackgroundSyncService.execute(serverUrl)`.

This means queued writes flush within ~3 seconds of reconnect rather than waiting up to 15 minutes for the next workmanager window.

The service is idempotent: calling `start()` again cancels the previous subscription cleanly via `stop()`.

---

## Conflict Resolution Policy

ɳClaw uses a simple, asymmetric policy:

| Data direction | Winner | Rationale |
|---|---|---|
| Server → cache (read data) | **Server wins** | Conversations, memories, and topics are authoritative on the server. A full replace (`ConflictAlgorithm.replace`) on upsert means stale cache rows are overwritten. |
| Cache → server (write queue) | **Client retries until accepted or failed** | User mutations are sent in creation order. If the server returns 4xx/5xx the entry is marked `failed` and surfaced to the user. There is no merge or last-write-wins logic for mutations. |

There is no optimistic-concurrency check (e.g. ETags or version columns) in v1. If two clients write the same memory record while offline, the last flush to reach the server wins. This is a known limitation and acceptable for the single-user scenario ɳClaw targets.

---

## Encryption at Rest

### Mobile (iOS, Android, macOS)

`EncryptedDbService` opens the SQLite file with `sqflite_sqlcipher`. The passphrase is:

1. Generated once per install: 32 bytes from `Random.secure()`, base64-encoded.
2. Stored in the platform keychain:
   - iOS / macOS: Keychain, accessibility `first_unlock`.
   - Android: `EncryptedSharedPreferences` backed by Android Keystore.
3. Read from the keychain on every subsequent open — never stored in plain text anywhere else.

The passphrase key in secure storage is `nclaw.db.passphrase.v1`. The `.v1` suffix allows future rotation by writing under a new key and re-encrypting.

### Desktop / CI / Web

On platforms where SQLCipher is not available (`kIsWeb` is true, or the platform is Linux / Windows), `EncryptedDbService` falls back to plain `sqflite`. The `OpenedDatabase.encrypted` flag reflects which path was taken. CI Flutter tests run on plain sqflite without needing a keychain.

### Caller interface

`EncryptedDbService.open(filename, version, onCreate, onUpgrade)` returns an `OpenedDatabase` whose `.db` property is typed `dynamic`. Both `sqflite` and `sqflite_sqlcipher` expose the same `Database` API surface (`execute`, `query`, `insert`, `rawQuery`, etc.), so call-sites do not branch on `encrypted`.

`OfflineCacheService` should migrate to use `EncryptedDbService.open` instead of calling `sqflite.openDatabase` directly. Until that migration is complete, `OfflineCacheService` uses unencrypted sqflite on all platforms.

---

## Developer Guidelines

### Adding a new data type to the offline layer

1. **Add a cache table** in `OfflineCacheService._initDb` under a new schema version. Increment the `version` argument and provide an `onUpgrade` handler that runs `CREATE TABLE IF NOT EXISTS ...` — never drop the write queue in an upgrade.

2. **Add typed read/write methods** on `OfflineCacheService` following the existing pattern:
   - Write: insert with `ConflictAlgorithm.replace`, `data` as `jsonEncode(map)`, `updated_at` as `DateTime.now().toIso8601String()`.
   - Read: `jsonDecode(row['data'])` cast to `Map<String, dynamic>`.

3. **Add a server pull** in `BackgroundSyncService._syncRecentData`. Fetch from the appropriate `/claw/<resource>?limit=N` endpoint, decode the response list, and call your new cache method in a loop. Keep the request timeout at 10 seconds to match existing calls.

4. **Use the write queue for user mutations** — never call the server directly from a UI action. Call `OfflineCacheService.instance.enqueueWrite(endpoint, method, body)` instead, then update the local cache optimistically so the UI reflects the change immediately.

5. **Open via `EncryptedDbService`** — new services that open their own SQLite files must use `EncryptedDbService.open` rather than calling sqflite directly. This ensures the file is encrypted on mobile without any additional branching in the new service.

6. **Do not hardcode server URLs** — `BackgroundSyncService.execute` and `ConnectivitySyncService` receive the server URL at call time from the connection provider. New sync code must follow the same pattern.

7. **Test offline behavior** — in widget tests, provide a fake `OfflineCacheService` (or use the real one against an in-memory sqflite). Do not skip offline path tests; the write queue and conflict resolution behaviour must be covered.

### Schema versioning

The current schema is `version: 1`. When adding columns to an existing table:

```dart
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE memories ADD COLUMN source TEXT');
  }
},
```

Never rename or drop columns in an upgrade — this breaks existing installs without a data migration plan.

### Clearing the cache

`OfflineCacheService.clearAll()` deletes all rows from all tables including the write queue. Call this only on sign-out or account removal. Do not call it on background sync errors — incomplete flushes should remain in the queue for the next cycle.
