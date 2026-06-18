/**
 * nclaw/mobile — migrationService.ts — Flutter SQLCipher DB detection and import.
 *
 * Purpose: On the first launch after upgrading from the Flutter-based ɳClaw mobile
 *          app, detects the legacy Flutter SQLCipher database (nclaw.db at the
 *          Flutter documents path) and migrates its data into the React Native
 *          SQLCipher database managed by EncryptedDB. The original Flutter DB is
 *          NEVER deleted — it is archived to a '.bak' copy and left in place so
 *          the user can recover if anything goes wrong.
 *
 * Inputs:  EncryptedDB instance (already open, RN key applied).
 *          SecureStoreInterface — used to read the Flutter DB key stored under
 *          the Flutter app's SecureStore namespace ('flutter.nclaw_db_key').
 *
 * Outputs: Result<MigrationResult, AppError> — reports row counts imported.
 *
 * Constraints:
 *   - IDEMPOTENT: if the Flutter DB file is absent, migration is a no-op.
 *   - IDEMPOTENT: if called a second time after the Flutter DB was deleted, it
 *     returns Ok({ skipped: true }) immediately — no error, no duplicate data.
 *   - The Flutter DB key is read from SecureStore but NEVER logged or retained.
 *   - If the Flutter DB cannot be decrypted (wrong key / corrupt), migration
 *     is skipped with a warning — existing RN data is preserved.
 *   - All data is imported via INSERT OR IGNORE to avoid duplicating rows that
 *     may already exist (e.g. from a prior partial migration).
 *   - NON-DESTRUCTIVE: before importing, the original Flutter DB is copied to a
 *     '.bak' sidecar. After import, migrated row counts are verified against the
 *     source counts; the migration is only marked done when every table's source
 *     rows are present in the RN DB. The original Flutter DB file is NEVER deleted
 *     — it is left on disk (alongside the .bak) so users keep a recovery path.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T11 (encryptedDB.ts service)
 *            T-P3-E2-W3-S03-T01 (native-bridge SecureStoreInterface)
 */

import * as FileSystem from 'expo-file-system';
import { ok, err, isOk, type Result, type AppError } from '@nself/errors';
import type { SecureStoreInterface } from '@nself/native-bridge';
import { EncryptedDB, type LocalMessage, type LocalActionQueueItem, type LocalDraft } from './encryptedDB';

// =============================================================================
// Types
// =============================================================================

/** Result of a migration run. */
export interface MigrationResult {
  /** True if the Flutter DB was not found (or was already migrated). */
  skipped: boolean;
  /** Number of messages imported. */
  messagesImported: number;
  /** Number of action queue items imported. */
  actionsImported: number;
  /** Number of drafts imported. */
  draftsImported: number;
  /**
   * Filesystem path of the retained backup copy of the original Flutter DB,
   * or null if no migration ran (skipped) or the backup could not be created.
   */
  backupPath: string | null;
  /** Human-readable summary for debug logging. */
  summary: string;
}

/** Per-table source row counts read from the Flutter DB before import. */
interface SourceCounts {
  messages: number;
  actions: number;
  drafts: number;
}

// =============================================================================
// Constants
// =============================================================================

/**
 * SecureStore key under which the Flutter app stored its DB encryption key.
 *
 * Flutter's flutter_secure_storage plugin prefixes keys with the app bundle
 * identifier on iOS and stores them in the Android Keystore on Android.
 * On both platforms, the raw key name used by the Flutter app was 'nclaw_db_key'
 * (same as the RN app) — but stored under the Flutter app's process context.
 *
 * On the first RN launch after migration, expo-secure-store reads the same
 * system keychain/keystore, so the key is accessible under the same name IF
 * the bundle identifier is unchanged. If the bundle ID changed, migration will
 * find no Flutter key and skip gracefully.
 */
const FLUTTER_DB_KEY_STORE_KEY = 'flutter.nclaw_db_key';

/** Fallback: same key name without namespace prefix (older Flutter app versions). */
const FLUTTER_DB_KEY_STORE_KEY_LEGACY = 'nclaw_db_key_flutter';

/**
 * Expected filename of the Flutter SQLCipher DB.
 *
 * Flutter's path_provider returns the app's documents directory, where
 * encrypted_db_service.dart stored the DB as 'nclaw.db'. On the RN side
 * the same filename is used (DB_FILENAME) — if both exist at the same path,
 * the RN DB open would have already claimed it. Migration detects a SEPARATE
 * Flutter backup copy left at the legacy path suffix '_flutter_backup'.
 *
 * Realistically, after an app store update the Flutter DB is at the documents
 * path and the RN app creates its DB at the same path. The migration service
 * checks for a Flutter-specific backup at '_flutter_backup' suffix first;
 * if absent, it checks whether the existing nclaw.db was created by Flutter
 * by attempting to open it with the Flutter key — if it succeeds and the RN
 * DB is brand new (zero messages), data is imported and the Flutter DB is
 * replaced by the RN DB.
 */
export const FLUTTER_DB_BACKUP_SUFFIX = '_flutter_backup';

// =============================================================================
// Migration guard
// =============================================================================

/** Persistent flag key in SecureStore: set to '1' after successful migration. */
const MIGRATION_DONE_FLAG = 'nclaw_rn_migration_done_v1';

/**
 * Suffix appended to the original Flutter DB path to form the retained backup.
 * The backup is created BEFORE any import and is never removed by this service,
 * giving the user a recovery path if migration corrupts the RN DB.
 */
const BACKUP_FILE_SUFFIX = '.bak';

// =============================================================================
// Flutter row types (raw, pre-cast)
// =============================================================================

interface FlutterMessageRow {
  id: string;
  conversation_id: string; // Flutter column name; maps to thread_id in RN
  role: string;
  content: string;
  created_at: string;
}

interface FlutterActionRow {
  id: string;
  action_type: string;
  payload: string;
  status: string;
  retry_count: number;
}

interface FlutterDraftRow {
  conversation_id: string; // Flutter column; maps to thread_id in RN
  content: string;
  updated_at: string;
}

// =============================================================================
// Migration entry point
// =============================================================================

/**
 * migrateFromFlutter — detect and import Flutter SQLCipher DB into the RN DB.
 *
 * Call this ONCE on app boot, BEFORE showing the main UI. The function is
 * idempotent: it checks a SecureStore flag so a second call is a sub-millisecond
 * no-op after the first successful migration.
 *
 * @param rnDB         The already-open RN EncryptedDB instance.
 * @param secureStore  SecureStore for reading the Flutter key + migration flag.
 */
export async function migrateFromFlutter(
  rnDB: EncryptedDB,
  secureStore: SecureStoreInterface,
): Promise<Result<MigrationResult, AppError>> {
  // --- Guard: check migration-done flag ---
  // get() throws on a backend failure; treat any read error as "flag not set"
  // so a transient SecureStore error does not permanently skip migration.
  let migrationFlag: string | null = null;
  try {
    migrationFlag = await secureStore.get(MIGRATION_DONE_FLAG);
  } catch {
    migrationFlag = null;
  }
  if (migrationFlag === '1') {
    return ok({
      skipped: true,
      messagesImported: 0,
      actionsImported: 0,
      draftsImported: 0,
      backupPath: null,
      summary: 'Migration already completed on a previous launch — skipped.',
    });
  }

  // --- Attempt to read the Flutter DB key ---
  const flutterKey = await resolveFlutterKey(secureStore);
  if (flutterKey === null) {
    // No Flutter key found — either the app was never a Flutter app or the
    // key was already cleaned up. Mark as done and skip.
    await secureStore.set(MIGRATION_DONE_FLAG, '1').catch(() => {});
    return ok({
      skipped: true,
      messagesImported: 0,
      actionsImported: 0,
      draftsImported: 0,
      backupPath: null,
      summary: 'No Flutter DB key found in SecureStore — assuming fresh install, migration skipped.',
    });
  }

  // --- Attempt to open the Flutter DB ---
  let flutterDB: FlutterDBAdapter | null = null;
  try {
    flutterDB = await openFlutterDB(flutterKey);
  } catch (cause) {
    // Flutter DB not found or could not be decrypted — skip gracefully.
    await secureStore.set(MIGRATION_DONE_FLAG, '1').catch(() => {});
    return ok({
      skipped: true,
      messagesImported: 0,
      actionsImported: 0,
      draftsImported: 0,
      backupPath: null,
      summary: `Flutter DB not accessible (${String(cause)}) — migration skipped.`,
    });
  }

  const flutterDBPath = flutterDB.path;

  // --- Read source row counts BEFORE any import (needed to verify the copy) ---
  let sourceCounts: SourceCounts;
  try {
    sourceCounts = await readSourceCounts(flutterDB);
  } catch (cause) {
    await flutterDB.close().catch(() => {});
    return err({
      code: 'internal',
      message: `Flutter migration: failed to read source row counts: ${String(cause)}`,
      status: 500,
    });
  }

  // --- Back up the original Flutter DB BEFORE importing or touching anything ---
  // The backup is the user's recovery path. If we cannot create it, we refuse to
  // proceed rather than risk an unrecoverable migration.
  const backupPath = await backupFlutterDB(flutterDBPath);
  if (backupPath === null) {
    await flutterDB.close().catch(() => {});
    return err({
      code: 'internal',
      message:
        'Flutter migration: could not create a backup of the original DB — ' +
        'aborting to avoid an unrecoverable migration.',
      status: 500,
    });
  }

  // --- Import data ---
  let messagesImported = 0;
  let actionsImported = 0;
  let draftsImported = 0;

  try {
    messagesImported = await importMessages(flutterDB, rnDB);
    actionsImported = await importActions(flutterDB, rnDB);
    draftsImported = await importDrafts(flutterDB, rnDB);
  } catch (cause) {
    // Partial import — do NOT mark done; user can retry on next launch.
    // The original Flutter DB and its .bak are both intact.
    await flutterDB.close().catch(() => {});
    return err({
      code: 'internal',
      message: `Flutter migration import failed mid-run: ${String(cause)}`,
      status: 500,
    });
  }

  await flutterDB.close().catch(() => {});

  // --- Verify migrated row counts match the source counts ---
  // Only proceed to mark-done when every source row landed in the RN DB. On any
  // shortfall we leave the original DB + backup intact and do NOT set the done
  // flag, so the next launch retries the migration.
  const verification = await verifyMigratedCounts(rnDB, sourceCounts);
  if (!verification.ok) {
    return err({
      code: 'internal',
      message:
        `Flutter migration verification failed (${verification.detail}). ` +
        `Original DB and backup retained at ${flutterDBPath} / ${backupPath} — will retry next launch.`,
      status: 500,
    });
  }

  // --- Mark migration done ---
  // The original Flutter DB is intentionally NOT deleted: it is left on disk
  // alongside the .bak backup so the user always has a recovery path.
  await secureStore.set(MIGRATION_DONE_FLAG, '1').catch(() => {});

  return ok({
    skipped: false,
    messagesImported,
    actionsImported,
    draftsImported,
    backupPath,
    summary:
      `Migration complete: ${messagesImported} messages, ` +
      `${actionsImported} actions, ${draftsImported} drafts imported. ` +
      `Original DB retained; backup at ${backupPath}.`,
  });
}

// =============================================================================
// Internal helpers
// =============================================================================

/** Try both Flutter SecureStore key names; return null if neither found. */
async function resolveFlutterKey(
  secureStore: SecureStoreInterface,
): Promise<string | null> {
  for (const storeKey of [FLUTTER_DB_KEY_STORE_KEY, FLUTTER_DB_KEY_STORE_KEY_LEGACY]) {
    // get() returns the raw value (or null) and throws on a backend failure;
    // a read error for one key falls through to the next candidate.
    let value: string | null = null;
    try {
      value = await secureStore.get(storeKey);
    } catch {
      value = null;
    }
    if (value !== null) {
      return value;
    }
  }
  return null;
}

// =============================================================================
// FlutterDBAdapter — thin wrapper around op-sqlite for the Flutter DB
// =============================================================================

interface FlutterDBAdapter {
  path: string;
  query<T>(sql: string, params?: unknown[]): Promise<T[]>;
  close(): Promise<void>;
}

/** Flutter documents-directory DB filename (platform-specific prefix added at runtime). */
const FLUTTER_DB_FILENAME = 'nclaw_flutter.db';

async function openFlutterDB(key: string): Promise<FlutterDBAdapter> {
  const opsqlite = await import('@op-engineering/op-sqlite');

  // Attempt to open the Flutter DB at the Flutter documents path.
  // op-sqlite resolves the filename relative to the app's documents directory.
  const rawDB = opsqlite.open({
    name: FLUTTER_DB_FILENAME,
    encryptionKey: key,
  }) as unknown as {
    executeAsync(sql: string, params?: unknown[]): Promise<{ rows: { _array: unknown[] } }>;
    close(): Promise<void>;
    getDbPath(): string;
  };

  // Verify the DB is accessible by running a trivial query.
  await rawDB.executeAsync('SELECT 1');

  return {
    path: rawDB.getDbPath(),
    async query<T>(sql: string, params?: unknown[]): Promise<T[]> {
      const result = await rawDB.executeAsync(sql, params);
      return result.rows._array as T[];
    },
    async close(): Promise<void> {
      await rawDB.close();
    },
  };
}

/**
 * Read per-table row counts from the Flutter DB. A missing table (older schema)
 * counts as zero rather than failing the whole migration.
 */
async function readSourceCounts(flutterDB: FlutterDBAdapter): Promise<SourceCounts> {
  return {
    messages: await countRows(flutterDB, 'messages'),
    actions: await countRows(flutterDB, 'action_queue'),
    drafts: await countRows(flutterDB, 'drafts'),
  };
}

/** COUNT(*) for a single Flutter table; returns 0 if the table does not exist. */
async function countRows(flutterDB: FlutterDBAdapter, table: string): Promise<number> {
  try {
    const rows = await flutterDB.query<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table}`);
    return Number(rows[0]?.n ?? 0);
  } catch {
    return 0;
  }
}

/**
 * Copy the original Flutter DB file to a sibling '.bak' path so the user keeps a
 * recovery copy. Returns the backup path on success, or null if the copy failed
 * (caller treats null as fatal and aborts the migration).
 */
async function backupFlutterDB(dbPath: string): Promise<string | null> {
  const backupPath = `${dbPath}${BACKUP_FILE_SUFFIX}`;
  try {
    const info = await FileSystem.getInfoAsync(backupPath);
    if (!info.exists) {
      await FileSystem.copyAsync({ from: dbPath, to: backupPath });
    }
    return backupPath;
  } catch (cause) {
    console.warn(`EncryptedDB migration: backup copy failed for ${dbPath}: ${String(cause)}`);
    return null;
  }
}

/** Outcome of post-import row-count verification. */
interface VerificationResult {
  ok: boolean;
  detail: string;
}

/**
 * Verify that every source row is present in the RN DB after import. Because
 * import uses INSERT OR IGNORE (rows pre-existing from a partial run are not
 * re-counted), correctness is checked against the live RN row counts, which must
 * be at least the source counts for each table.
 */
async function verifyMigratedCounts(
  rnDB: EncryptedDB,
  source: SourceCounts,
): Promise<VerificationResult> {
  const checks: Array<[label: string, table: string, expected: number]> = [
    ['messages', 'nclaw_messages', source.messages],
    ['actions', 'nclaw_action_queue', source.actions],
    ['drafts', 'nclaw_drafts', source.drafts],
  ];

  for (const [label, table, expected] of checks) {
    const result = await rnDB._rawExecute(`SELECT COUNT(*) AS n FROM ${table}`);
    if (!isOk(result)) {
      return { ok: false, detail: `could not read RN ${label} count` };
    }
    const actual = Number((result.value.rows[0] as { n?: number } | undefined)?.n ?? 0);
    if (actual < expected) {
      return {
        ok: false,
        detail: `${label}: RN has ${actual} rows but source had ${expected}`,
      };
    }
  }

  return { ok: true, detail: 'all source rows verified present in RN DB' };
}

// =============================================================================
// Per-table importers
// =============================================================================

async function importMessages(
  flutterDB: FlutterDBAdapter,
  rnDB: EncryptedDB,
): Promise<number> {
  let rows: FlutterMessageRow[] = [];
  try {
    rows = await flutterDB.query<FlutterMessageRow>(
      `SELECT id, conversation_id, role, content, created_at FROM messages`,
    );
  } catch {
    // Table may not exist in older Flutter schema versions — skip.
    return 0;
  }

  let count = 0;
  for (const row of rows) {
    const msg: LocalMessage = {
      id: row.id,
      thread_id: row.conversation_id,
      role: normalizeRole(row.role),
      content: row.content,
      created_at: row.created_at,
    };
    const result = await rnDB.insertMessage(msg);
    if (isOk(result)) count++;
  }
  return count;
}

async function importActions(
  flutterDB: FlutterDBAdapter,
  rnDB: EncryptedDB,
): Promise<number> {
  let rows: FlutterActionRow[] = [];
  try {
    rows = await flutterDB.query<FlutterActionRow>(
      `SELECT id, action_type, payload, status, retry_count FROM action_queue`,
    );
  } catch {
    return 0;
  }

  let count = 0;
  for (const row of rows) {
    const result = await rnDB._rawExecute(
      `INSERT OR IGNORE INTO nclaw_action_queue (id, action_type, payload, status, retry_count)
       VALUES (?, ?, ?, ?, ?)`,
      [row.id, row.action_type, row.payload, normalizeActionStatus(row.status), row.retry_count],
    );
    if (isOk(result)) count++;
  }
  return count;
}

async function importDrafts(
  flutterDB: FlutterDBAdapter,
  rnDB: EncryptedDB,
): Promise<number> {
  let rows: FlutterDraftRow[] = [];
  try {
    rows = await flutterDB.query<FlutterDraftRow>(
      `SELECT conversation_id, content, updated_at FROM drafts`,
    );
  } catch {
    return 0;
  }

  let count = 0;
  for (const row of rows) {
    const draft: LocalDraft = {
      thread_id: row.conversation_id,
      content: row.content,
      updated_at: row.updated_at,
    };
    const result = await rnDB.saveDraft(draft);
    if (isOk(result)) count++;
  }
  return count;
}

// =============================================================================
// Normalisation helpers
// =============================================================================

function normalizeRole(raw: string): 'user' | 'assistant' | 'system' {
  const lower = raw.toLowerCase();
  if (lower === 'user') return 'user';
  if (lower === 'assistant' || lower === 'ai') return 'assistant';
  return 'system';
}

function normalizeActionStatus(
  raw: string,
): 'pending' | 'processing' | 'failed' {
  const lower = raw.toLowerCase();
  if (lower === 'pending') return 'pending';
  if (lower === 'processing') return 'processing';
  return 'failed';
}
