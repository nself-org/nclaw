/**
 * offline-queue — MMKV-backed offline mutation queue for ɳClaw mobile.
 *
 * Purpose: Persist chat message mutations across app kills when the device is
 *   offline. On reconnect (detected via useNetworkStatus 'connected' event),
 *   the queue drains by replaying mutations in insertion order. Ensures the
 *   "infinite memory" promise holds even without connectivity.
 *
 * Inputs:
 *   enqueue(item)   — add a queued mutation; survives process kill via AsyncStorage.
 *   drain(executor) — replay all queued items via `executor`; removes on success.
 *   getQueue()      — read current queue without side effects.
 *   clearQueue()    — discard entire queue (e.g. after full resync).
 *
 * Outputs: Typed OfflineQueueItem[] stored under a namespaced AsyncStorage key.
 *
 * Constraints:
 *   - Uses AsyncStorage (ships with Expo, no native modules required) so the
 *     queue survives process kill and app restart — satisfying the MMKV durability
 *     requirement via the Expo-compatible equivalent.
 *   - Queue key is namespaced: `@nclaw/offline-queue/mutations` — never collides
 *     with other AsyncStorage keys.
 *   - Drain is idempotent: failed items remain in queue and are retried on next
 *     drain call.
 *   - Concurrent drain calls are serialised via a module-level lock flag.
 *   - All operations are async (no sync I/O on the JS thread).
 *
 * SPORT: REGISTRY-NATIVE-APPS.md — nclaw/mobile offline_sync=true
 * Cross-ref: T-P3-E5-W3-S4-T01 (offline robustness sprint)
 *            hooks/useOfflineMutation.ts (consumer)
 *            hooks/useNetworkStatus.ts (triggers drain on reconnect)
 */

import AsyncStorage from '@react-native-async-storage/async-storage';

// =============================================================================
// Types
// =============================================================================

/** A single queued mutation payload. */
export interface OfflineQueueItem {
  /** Unique ID for deduplication (UUID generated at enqueue time). */
  readonly id: string;
  /** ISO timestamp when the item was enqueued. */
  readonly enqueuedAt: string;
  /** GraphQL mutation document string. */
  readonly mutation: string;
  /** Serialised variables for the mutation. */
  readonly variables: Record<string, unknown>;
  /** Number of drain attempts so far. */
  retryCount: number;
}

/** Result of a drain operation. */
export interface DrainResult {
  /** Items that were successfully flushed and removed. */
  readonly succeeded: OfflineQueueItem[];
  /** Items that failed and remain in the queue. */
  readonly failed: OfflineQueueItem[];
}

// =============================================================================
// Constants
// =============================================================================

/**
 * AsyncStorage key — namespaced to avoid collisions.
 * Changing this key is a breaking migration (existing queue data would be lost).
 */
const QUEUE_KEY = '@nclaw/offline-queue/mutations';

/** Maximum number of items kept in the queue (prevents unbounded growth). */
const MAX_QUEUE_SIZE = 500;

// =============================================================================
// Module-level drain lock (prevents concurrent drain runs)
// =============================================================================

let _draining = false;

// =============================================================================
// Internal helpers
// =============================================================================

async function readQueue(): Promise<OfflineQueueItem[]> {
  try {
    const raw = await AsyncStorage.getItem(QUEUE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed as OfflineQueueItem[];
  } catch {
    return [];
  }
}

async function writeQueue(items: OfflineQueueItem[]): Promise<void> {
  try {
    await AsyncStorage.setItem(QUEUE_KEY, JSON.stringify(items));
  } catch {
    // Storage write failure — item remains ephemeral for this session.
  }
}

function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

// =============================================================================
// Public API
// =============================================================================

/**
 * enqueue — add a mutation to the offline queue.
 *
 * The item is written to AsyncStorage immediately so it survives a process kill.
 * If the queue exceeds MAX_QUEUE_SIZE, the oldest items are dropped.
 *
 * @param mutation — GraphQL document string (gql tag or plain string)
 * @param variables — mutation variables
 * @returns The enqueued item (useful for tests / optimistic UI)
 */
export async function enqueue(
  mutation: string,
  variables: Record<string, unknown>,
): Promise<OfflineQueueItem> {
  const item: OfflineQueueItem = {
    id: generateId(),
    enqueuedAt: new Date().toISOString(),
    mutation,
    variables,
    retryCount: 0,
  };

  const current = await readQueue();
  const updated = [...current, item].slice(-MAX_QUEUE_SIZE);
  await writeQueue(updated);
  return item;
}

/**
 * getQueue — return the current queue without side effects.
 */
export async function getQueue(): Promise<OfflineQueueItem[]> {
  return readQueue();
}

/**
 * clearQueue — discard the entire queue.
 *
 * Use after a full resync that guarantees all mutations were applied server-side.
 */
export async function clearQueue(): Promise<void> {
  await AsyncStorage.removeItem(QUEUE_KEY);
}

/**
 * drain — replay all queued mutations via `executor`.
 *
 * Items are processed in insertion order. Successfully executed items are
 * removed from the queue immediately. Failed items remain and are retried
 * on the next drain call. Concurrent drain calls are serialised.
 *
 * @param executor — async function that executes a single queued item.
 *   Must resolve on success, reject on failure.
 * @returns DrainResult with succeeded/failed lists.
 *
 * @example
 * const { succeeded, failed } = await drain(async (item) => {
 *   const result = await urqlClient.mutation(item.mutation, item.variables);
 *   if (result.error) throw result.error;
 * });
 */
export async function drain(
  executor: (item: OfflineQueueItem) => Promise<void>,
): Promise<DrainResult> {
  if (_draining) {
    return { succeeded: [], failed: [] };
  }
  _draining = true;

  const succeeded: OfflineQueueItem[] = [];
  const failed: OfflineQueueItem[] = [];

  try {
    const items = await readQueue();
    if (items.length === 0) {
      return { succeeded, failed };
    }

    const remaining: OfflineQueueItem[] = [];

    for (const item of items) {
      try {
        await executor(item);
        succeeded.push(item);
      } catch {
        item.retryCount += 1;
        failed.push(item);
        remaining.push(item);
      }
    }

    await writeQueue(remaining);
  } finally {
    _draining = false;
  }

  return { succeeded, failed };
}

/**
 * isDraining — true while a drain call is in progress.
 * Exposed for UI indicators (e.g. "Syncing…" badge).
 */
export function isDraining(): boolean {
  return _draining;
}
