/**
 * nclaw/mobile — encryptedDB.ts — SQLCipher encrypted local database service.
 *
 * Purpose: Manages an AES-256 SQLCipher database for on-device persistence of
 *          conversation messages, pending action queue, and message drafts.
 *          Provides the backing store for offline-first ɳClaw operation.
 *
 * Inputs:  SecureStoreInterface — injected at open() to retrieve/generate the DB key.
 *          Op-SQLite with SQLCipher compilation flag (SQLCIPHER=1).
 *
 * Outputs: Typed CRUD methods for nclaw_messages, nclaw_action_queue, nclaw_drafts.
 *          Result<T, AppError> — no untyped throws escape this module.
 *
 * Constraints:
 *   - DB key is NEVER logged, serialized to JS bundle, or embedded in source.
 *   - DB fails CLOSED if key derivation fails — no plaintext fallback.
 *   - open() is idempotent: multiple calls return the same DB handle.
 *   - All table operations are async; SQLite I/O must not block the React Native thread.
 *   - Migration from Flutter SQLCipher DB is handled by migrationService.ts.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E2-W3-S03-T01 (native-bridge SecureStoreInterface)
 *            T-P3-E4-W2-S3-T01 (nclaw/mobile scaffold)
 *            T-P3-E4-W2-S3-T09 (offline cache integration)
 */

import { ok, err, isOk, type Result, type AppError } from '@nself/errors';
import type { SecureStoreInterface } from '@nself/native-bridge';

// =============================================================================
// Schema types
// =============================================================================

/** A cached conversation message stored locally. */
export interface LocalMessage {
  /** UUID — stable across sync. */
  readonly id: string;
  /** Conversation/thread UUID this message belongs to. */
  readonly thread_id: string;
  /** Sender role. */
  readonly role: 'user' | 'assistant' | 'system';
  /** Full text content of the message. */
  readonly content: string;
  /** UTC ISO 8601 timestamp. */
  readonly created_at: string;
}

/** A pending operation queued while offline. */
export interface LocalActionQueueItem {
  /** UUID — used for deduplication on sync. */
  readonly id: string;
  /** Discriminator for the action handler. */
  readonly action_type: string;
  /** JSON-serialised action payload. */
  readonly payload: string;
  /** Lifecycle status. */
  readonly status: 'pending' | 'processing' | 'failed';
  /** Number of sync attempts made so far. */
  readonly retry_count: number;
}

/** A message draft persisted per thread. */
export interface LocalDraft {
  /** Thread UUID this draft belongs to. */
  readonly thread_id: string;
  /** Current draft text. */
  readonly content: string;
  /** UTC ISO 8601 timestamp of last edit. */
  readonly updated_at: string;
}

// =============================================================================
// Lazy op-sqlite import
// =============================================================================

/**
 * Lazily import @op-engineering/op-sqlite so tests can stub it without
 * loading native modules. This also prevents the import from crashing in
 * CI environments that lack the native SQLCipher library.
 */
async function getOPSQLite(): Promise<typeof import('@op-engineering/op-sqlite')> {
  // Dynamic import isolates native-module load from test environments.
  const mod = await import('@op-engineering/op-sqlite');
  return mod;
}

// =============================================================================
// DB key management
// =============================================================================

/** SecureStore key under which the 32-byte hex DB key is stored. */
const DB_KEY_SECURE_STORE_KEY = 'nclaw_db_key';

/** DB filename written to the app's documents directory. */
export const DB_FILENAME = 'nclaw.db';

/**
 * Derive the database encryption key.
 *
 * Algorithm:
 *   1. Attempt to retrieve an existing key from SecureStore.
 *   2. If no key exists, generate a 32-byte cryptographically random key,
 *      persist it to SecureStore, and return it.
 *   3. If SecureStore fails on set, bubble the error — DB must NOT open without a key.
 *
 * The key is returned as a hex string (64 chars) for use in the SQLCipher PRAGMA.
 * It is NEVER logged, stored in memory longer than needed, or included in error messages.
 */
async function deriveDBKey(
  secureStore: SecureStoreInterface,
): Promise<Result<string, AppError>> {
  const getResult = await secureStore.getItem(DB_KEY_SECURE_STORE_KEY);
  if (!isOk(getResult)) {
    return err({
      code: 'internal',
      message: 'EncryptedDB: failed to read DB key from SecureStore',
      status: 500,
    });
  }

  if (getResult.value !== null) {
    return ok(getResult.value);
  }

  // No key found — generate a new one.
  // generateHexKey throws if crypto.getRandomValues is unavailable (fail-closed).
  let newKey: string;
  try {
    newKey = generateHexKey(32);
  } catch (cause) {
    return err({
      code: 'internal',
      message: `EncryptedDB: ${String(cause)}`,
      status: 500,
    });
  }
  const setResult = await secureStore.setItem(DB_KEY_SECURE_STORE_KEY, newKey);
  if (!isOk(setResult)) {
    return err({
      code: 'internal',
      message: 'EncryptedDB: failed to persist new DB key to SecureStore',
      status: 500,
    });
  }

  return ok(newKey);
}

/**
 * Generate a cryptographically random hex string of `byteLength` bytes.
 *
 * Requires React Native's `crypto.getRandomValues` (available in Hermes >= 0.12 /
 * React Native >= 0.73 — the project minimum). Throws if the CSPRNG is unavailable
 * so the caller (deriveDBKey) propagates an error and the DB remains CLOSED.
 * A Math.random fallback is deliberately absent: weak key material is more
 * dangerous than a hard startup failure.
 *
 * @throws {Error} if `crypto.getRandomValues` is not available.
 */
function generateHexKey(byteLength: number): string {
  if (typeof globalThis.crypto?.getRandomValues !== 'function') {
    // Fail CLOSED — do not fall back to Math.random or any non-CSPRNG source.
    // If this throws, deriveDBKey returns Err and EncryptedDB.open() returns Err,
    // preventing the DB from opening with a weak or predictable key.
    throw new Error(
      'EncryptedDB: crypto.getRandomValues is unavailable. ' +
      'React Native >= 0.73 (Hermes) is required for secure DB key generation. ' +
      'Refusing to generate a DB key with a non-cryptographic source.',
    );
  }
  const bytes = new Uint8Array(byteLength);
  globalThis.crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// =============================================================================
// Schema DDL
// =============================================================================

/**
 * DDL statements executed once on first open (CREATE TABLE IF NOT EXISTS).
 *
 * Schema mirrors the Flutter encrypted_db_service.dart schema so the
 * migrationService can import Flutter data without transformation.
 */
const SCHEMA_DDL = [
  `CREATE TABLE IF NOT EXISTS nclaw_messages (
    id         TEXT PRIMARY KEY NOT NULL,
    thread_id  TEXT NOT NULL,
    role       TEXT NOT NULL CHECK(role IN ('user','assistant','system')),
    content    TEXT NOT NULL,
    created_at TEXT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_messages_thread ON nclaw_messages(thread_id)`,
  `CREATE TABLE IF NOT EXISTS nclaw_action_queue (
    id           TEXT PRIMARY KEY NOT NULL,
    action_type  TEXT NOT NULL,
    payload      TEXT NOT NULL,
    status       TEXT NOT NULL CHECK(status IN ('pending','processing','failed')),
    retry_count  INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS nclaw_drafts (
    thread_id   TEXT PRIMARY KEY NOT NULL,
    content     TEXT NOT NULL,
    updated_at  TEXT NOT NULL
  )`,
] as const;

// =============================================================================
// EncryptedDB class
// =============================================================================

/** Opaque handle to the opened SQLCipher database. */
// op-sqlite does not export a typed DB handle interface; we use `unknown` with
// assertion helpers below to stay strictly typed without `any`.
type OPSQLiteDB = {
  executeAsync(query: string, params?: unknown[]): Promise<{ rows: { _array: unknown[] } }>;
  close(): Promise<void>;
};

/**
 * EncryptedDB — typed service for the nclaw SQLCipher on-device database.
 *
 * Lifecycle:
 *   1. Call EncryptedDB.open(secureStore) to obtain a ready-to-use instance.
 *   2. Use insert/query/delete methods for typed CRUD.
 *   3. Call close() when the app backgrounds (optional — OS handles this too).
 *
 * Thread safety: op-sqlite serialises writes internally; concurrent reads are safe.
 */
export class EncryptedDB {
  /** Singleton instance — only one DB connection per process. */
  private static _instance: EncryptedDB | null = null;

  private constructor(private readonly db: OPSQLiteDB) {}

  /**
   * Open the SQLCipher database. Idempotent — returns the existing instance if
   * already open.
   *
   * Steps:
   *   1. Derive key from SecureStore (generate if missing).
   *   2. Open nclaw.db via @op-engineering/op-sqlite with the derived key.
   *   3. Apply schema DDL (CREATE TABLE IF NOT EXISTS — safe to re-run).
   *
   * Returns Err if key derivation fails, native open fails, or DDL fails.
   * In all error cases the DB remains CLOSED — no plaintext fallback.
   */
  static async open(
    secureStore: SecureStoreInterface,
  ): Promise<Result<EncryptedDB, AppError>> {
    if (EncryptedDB._instance !== null) {
      return ok(EncryptedDB._instance);
    }

    // Step 1: derive key
    const keyResult = await deriveDBKey(secureStore);
    if (!isOk(keyResult)) {
      return err(keyResult.error);
    }
    const key = keyResult.value;

    // Step 2: open SQLCipher DB
    let rawDB: OPSQLiteDB;
    try {
      const opsqlite = await getOPSQLite();
      // @op-engineering/op-sqlite open() with SQLCipher key pragma.
      // The `encryptionKey` option is the SQLCipher passphrase applied via
      // `PRAGMA key = "x'<hex>'"` immediately after open.
      rawDB = opsqlite.open({
        name: DB_FILENAME,
        encryptionKey: key,
      }) as unknown as OPSQLiteDB;
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB: failed to open SQLCipher DB: ${String(cause)}`,
        status: 500,
      });
    }

    // Step 3: apply schema
    try {
      for (const ddl of SCHEMA_DDL) {
        await rawDB.executeAsync(ddl);
      }
    } catch (cause) {
      await rawDB.close().catch(() => {});
      return err({
        code: 'internal',
        message: `EncryptedDB: schema migration failed: ${String(cause)}`,
        status: 500,
      });
    }

    const instance = new EncryptedDB(rawDB);
    EncryptedDB._instance = instance;
    return ok(instance);
  }

  /**
   * Close the database and clear the singleton.
   *
   * Safe to call multiple times; subsequent calls are no-ops.
   */
  async close(): Promise<void> {
    if (EncryptedDB._instance === null) return;
    await this.db.close().catch(() => {});
    EncryptedDB._instance = null;
  }

  // ---------------------------------------------------------------------------
  // nclaw_messages
  // ---------------------------------------------------------------------------

  /**
   * Insert or replace a message in nclaw_messages.
   *
   * Uses INSERT OR REPLACE so the operation is idempotent on conflict(id).
   */
  async insertMessage(msg: LocalMessage): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `INSERT OR REPLACE INTO nclaw_messages (id, thread_id, role, content, created_at)
         VALUES (?, ?, ?, ?, ?)`,
        [msg.id, msg.thread_id, msg.role, msg.content, msg.created_at],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.insertMessage failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Query all messages for a thread, ordered by created_at ascending.
   */
  async getMessagesByThread(
    threadId: string,
  ): Promise<Result<LocalMessage[], AppError>> {
    try {
      const result = await this.db.executeAsync(
        `SELECT id, thread_id, role, content, created_at
         FROM nclaw_messages
         WHERE thread_id = ?
         ORDER BY created_at ASC`,
        [threadId],
      );
      const rows = result.rows._array as LocalMessage[];
      return ok(rows);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.getMessagesByThread failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Delete a single message by ID.
   */
  async deleteMessage(id: string): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `DELETE FROM nclaw_messages WHERE id = ?`,
        [id],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.deleteMessage failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // nclaw_action_queue
  // ---------------------------------------------------------------------------

  /**
   * Enqueue a new action. Status defaults to 'pending'.
   */
  async enqueueAction(
    item: Omit<LocalActionQueueItem, 'status' | 'retry_count'>,
  ): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `INSERT OR IGNORE INTO nclaw_action_queue (id, action_type, payload, status, retry_count)
         VALUES (?, ?, ?, 'pending', 0)`,
        [item.id, item.action_type, item.payload],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.enqueueAction failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Fetch all actions with the given status.
   */
  async getActions(
    status: LocalActionQueueItem['status'],
  ): Promise<Result<LocalActionQueueItem[], AppError>> {
    try {
      const result = await this.db.executeAsync(
        `SELECT id, action_type, payload, status, retry_count
         FROM nclaw_action_queue
         WHERE status = ?
         ORDER BY rowid ASC`,
        [status],
      );
      const rows = result.rows._array as LocalActionQueueItem[];
      return ok(rows);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.getActions failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Update the status and increment retry_count for an action.
   */
  async updateActionStatus(
    id: string,
    status: LocalActionQueueItem['status'],
  ): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `UPDATE nclaw_action_queue
         SET status = ?, retry_count = retry_count + 1
         WHERE id = ?`,
        [status, id],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.updateActionStatus failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Delete a completed action from the queue.
   */
  async deleteAction(id: string): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `DELETE FROM nclaw_action_queue WHERE id = ?`,
        [id],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.deleteAction failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // nclaw_drafts
  // ---------------------------------------------------------------------------

  /**
   * Upsert a message draft for a thread (one draft per thread).
   */
  async saveDraft(draft: LocalDraft): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `INSERT OR REPLACE INTO nclaw_drafts (thread_id, content, updated_at)
         VALUES (?, ?, ?)`,
        [draft.thread_id, draft.content, draft.updated_at],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.saveDraft failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Retrieve the current draft for a thread. Returns Ok(null) if none exists.
   */
  async getDraft(
    threadId: string,
  ): Promise<Result<LocalDraft | null, AppError>> {
    try {
      const result = await this.db.executeAsync(
        `SELECT thread_id, content, updated_at
         FROM nclaw_drafts
         WHERE thread_id = ?
         LIMIT 1`,
        [threadId],
      );
      const rows = result.rows._array as LocalDraft[];
      return ok(rows[0] ?? null);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.getDraft failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  /**
   * Delete the draft for a thread (after send or discard).
   */
  async deleteDraft(threadId: string): Promise<Result<void, AppError>> {
    try {
      await this.db.executeAsync(
        `DELETE FROM nclaw_drafts WHERE thread_id = ?`,
        [threadId],
      );
      return ok(undefined);
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB.deleteDraft failed: ${String(cause)}`,
        status: 500,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Raw access for migration
  // ---------------------------------------------------------------------------

  /**
   * Execute a raw SQL statement. Used by migrationService for bulk import.
   *
   * @internal — not part of the public API; exposed only for migrationService.
   */
  async _rawExecute(
    sql: string,
    params?: unknown[],
  ): Promise<Result<{ rows: unknown[] }, AppError>> {
    try {
      const result = await this.db.executeAsync(sql, params);
      return ok({ rows: result.rows._array });
    } catch (cause) {
      return err({
        code: 'internal',
        message: `EncryptedDB._rawExecute failed: ${String(cause)}`,
        status: 500,
      });
    }
  }
}
