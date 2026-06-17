/**
 * nclaw/mobile — useEncryptedDB.ts — typed React hook for the local SQLCipher DB.
 *
 * Purpose: Provides typed CRUD operations for nclaw_messages, nclaw_action_queue,
 *          and nclaw_drafts. Manages DB lifecycle (open on mount, status tracking).
 *          Consumers never touch EncryptedDB directly — all operations go through
 *          this hook so error handling and loading state are consistent.
 *
 * Inputs:  SecureStoreInterface — injected via props so tests can provide a mock
 *          without touching the native SecureStore.
 * Outputs: { db, isReady, error, messages, drafts, actionQueue } — typed typed
 *          CRUD methods + status fields.
 *
 * Constraints:
 *   - DB open is async; all CRUD methods are gated on isReady.
 *   - Errors from individual operations are returned (not thrown) so UI can react.
 *   - The hook does NOT expose the DB key or any intermediate key material.
 *   - Designed for a single-instance use at the app root (Provider pattern).
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T11 (encryptedDB.ts service)
 *            T-P3-E2-W3-S03-T01 (native-bridge SecureStoreInterface)
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { err, isOk, type Result, type AppError } from '@nself/errors';
import type { SecureStoreInterface } from '@nself/native-bridge';
import {
  EncryptedDB,
  type LocalActionQueueItem,
  type LocalDraft,
  type LocalMessage,
} from '../services/encryptedDB';

// =============================================================================
// Hook return type
// =============================================================================

/** Status of the DB connection. */
export type DBStatus = 'idle' | 'opening' | 'ready' | 'error';

export interface UseEncryptedDBResult {
  /** Current DB lifecycle status. */
  status: DBStatus;
  /** True when the DB is open and ready for queries. */
  isReady: boolean;
  /** Non-null if DB open failed. Individual op errors are returned from each method. */
  openError: AppError | null;

  // --- nclaw_messages ---

  /** Insert or replace a message. */
  insertMessage(msg: LocalMessage): Promise<Result<void, AppError>>;
  /** Get all messages for a thread, oldest-first. */
  getMessagesByThread(threadId: string): Promise<Result<LocalMessage[], AppError>>;
  /** Delete a single message by ID. */
  deleteMessage(id: string): Promise<Result<void, AppError>>;

  // --- nclaw_action_queue ---

  /** Enqueue a new action (status defaults to 'pending'). */
  enqueueAction(
    item: Omit<LocalActionQueueItem, 'status' | 'retry_count'>,
  ): Promise<Result<void, AppError>>;
  /** Fetch actions by status. */
  getActions(
    status: LocalActionQueueItem['status'],
  ): Promise<Result<LocalActionQueueItem[], AppError>>;
  /** Update action status and increment retry_count. */
  updateActionStatus(
    id: string,
    status: LocalActionQueueItem['status'],
  ): Promise<Result<void, AppError>>;
  /** Delete a completed action from the queue. */
  deleteAction(id: string): Promise<Result<void, AppError>>;

  // --- nclaw_drafts ---

  /** Upsert the draft for a thread. */
  saveDraft(draft: LocalDraft): Promise<Result<void, AppError>>;
  /** Get the current draft for a thread (null if none). */
  getDraft(threadId: string): Promise<Result<LocalDraft | null, AppError>>;
  /** Delete a draft (after send or discard). */
  deleteDraft(threadId: string): Promise<Result<void, AppError>>;
}

// =============================================================================
// Not-ready stub helpers
// =============================================================================

/** Reusable "DB not ready" error for all stub operations. */
function dbNotReadyError(): AppError {
  return {
    code: 'internal',
    message: 'useEncryptedDB: DB is not open yet — wait for isReady',
    status: 500,
  };
}

function notReady<T>(): Promise<Result<T, AppError>> {
  return Promise.resolve(err<AppError>(dbNotReadyError()));
}

// =============================================================================
// Hook
// =============================================================================

/**
 * useEncryptedDB — React hook for the nclaw SQLCipher local database.
 *
 * IMPORTANT — `secureStore` MUST be referentially stable across renders.
 * The hook's useEffect lists `secureStore` as a dependency: if a new instance
 * is passed on every parent render (e.g. `new ExpoSecureStore()` inline), the
 * effect will re-run and attempt to re-open the DB on each render.
 * EncryptedDB.open() is idempotent (singleton guard), so no duplicate file
 * handle is created, but the `cancelled` flag race window grows unnecessarily.
 *
 * Correct usage patterns:
 *   // Option A — module-level singleton (preferred for app root):
 *   const SECURE_STORE = new ExpoSecureStore();
 *   function App() { const db = useEncryptedDB({ secureStore: SECURE_STORE }); ... }
 *
 *   // Option B — useMemo if the store must be created inside a component:
 *   const secureStore = useMemo(() => new ExpoSecureStore(), []);
 *   const db = useEncryptedDB({ secureStore });
 *
 *   // Option C — Context Provider (recommended for large apps):
 *   // Wrap at app root with <EncryptedDBProvider store={SECURE_STORE}>.
 *
 * Usage (at app root / context provider):
 *   const db = useEncryptedDB({ secureStore: SECURE_STORE });
 *   if (!db.isReady) return <SplashScreen />;
 *   // Now use db.insertMessage(), db.saveDraft(), etc.
 */
export function useEncryptedDB({
  secureStore,
}: {
  secureStore: SecureStoreInterface;
}): UseEncryptedDBResult {
  const [status, setStatus] = useState<DBStatus>('idle');
  const [openError, setOpenError] = useState<AppError | null>(null);
  const dbRef = useRef<EncryptedDB | null>(null);

  // Open DB on mount
  useEffect(() => {
    let cancelled = false;

    async function openDB(): Promise<void> {
      setStatus('opening');
      const result = await EncryptedDB.open(secureStore);

      if (cancelled) return;

      if (!isOk(result)) {
        setOpenError(result.error);
        setStatus('error');
        return;
      }

      dbRef.current = result.value;
      setStatus('ready');
    }

    openDB().catch((cause: unknown) => {
      if (cancelled) return;
      setOpenError({
        code: 'internal',
        message: `useEncryptedDB: unexpected open error: ${String(cause)}`,
        status: 500,
      });
      setStatus('error');
    });

    return () => {
      cancelled = true;
    };
  }, [secureStore]);

  const isReady = status === 'ready';

  // ---------------------------------------------------------------------------
  // nclaw_messages
  // ---------------------------------------------------------------------------

  const insertMessage = useCallback(
    (msg: LocalMessage): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.insertMessage(msg);
    },
    [isReady],
  );

  const getMessagesByThread = useCallback(
    (threadId: string): Promise<Result<LocalMessage[], AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.getMessagesByThread(threadId);
    },
    [isReady],
  );

  const deleteMessage = useCallback(
    (id: string): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.deleteMessage(id);
    },
    [isReady],
  );

  // ---------------------------------------------------------------------------
  // nclaw_action_queue
  // ---------------------------------------------------------------------------

  const enqueueAction = useCallback(
    (
      item: Omit<LocalActionQueueItem, 'status' | 'retry_count'>,
    ): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.enqueueAction(item);
    },
    [isReady],
  );

  const getActions = useCallback(
    (
      status: LocalActionQueueItem['status'],
    ): Promise<Result<LocalActionQueueItem[], AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.getActions(status);
    },
    [isReady],
  );

  const updateActionStatus = useCallback(
    (
      id: string,
      status: LocalActionQueueItem['status'],
    ): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.updateActionStatus(id, status);
    },
    [isReady],
  );

  const deleteAction = useCallback(
    (id: string): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.deleteAction(id);
    },
    [isReady],
  );

  // ---------------------------------------------------------------------------
  // nclaw_drafts
  // ---------------------------------------------------------------------------

  const saveDraft = useCallback(
    (draft: LocalDraft): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.saveDraft(draft);
    },
    [isReady],
  );

  const getDraft = useCallback(
    (threadId: string): Promise<Result<LocalDraft | null, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.getDraft(threadId);
    },
    [isReady],
  );

  const deleteDraft = useCallback(
    (threadId: string): Promise<Result<void, AppError>> => {
      if (!isReady || dbRef.current === null) return notReady();
      return dbRef.current.deleteDraft(threadId);
    },
    [isReady],
  );

  return {
    status,
    isReady,
    openError,
    insertMessage,
    getMessagesByThread,
    deleteMessage,
    enqueueAction,
    getActions,
    updateActionStatus,
    deleteAction,
    saveDraft,
    getDraft,
    deleteDraft,
  };
}
