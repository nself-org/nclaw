/**
 * useOfflineMutation — MMKV-backed offline mutation queue hook.
 *
 * Purpose: Single hook that wires the offline queue service with the network
 *   status hook. Mutations queued offline are automatically drained when the
 *   device reconnects. Provides an `isSyncing` flag for UI indicators.
 *
 * Inputs:
 *   executor    — async function that executes one OfflineQueueItem; injected
 *                 by the caller so the hook stays GraphQL-client-agnostic.
 *   onDrained?  — optional callback fired after each successful drain.
 *
 * Outputs:
 *   enqueueMutation  — enqueue a mutation; durable across process kills.
 *   isSyncing        — true while the queue is draining.
 *   queueSize        — current number of items waiting to be sent.
 *   drainNow()       — manually trigger a drain (e.g. after pull-to-refresh).
 *
 * Constraints:
 *   - Queue is stored in AsyncStorage under `@nclaw/offline-queue/mutations`.
 *   - Drain fires automatically on offline → online transition.
 *   - Re-registration of the connected listener is idempotent (useEffect cleanup).
 *   - Hook is safe to mount on multiple screens — queue operations are atomic.
 *
 * SPORT: REGISTRY-NATIVE-APPS.md — nclaw/mobile offline_sync=true
 * Cross-ref: T-P3-E5-W3-S4-T01
 *            services/offline-queue/index.ts (queue storage)
 *            hooks/useNetworkStatus.ts (triggers drain on reconnect)
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import {
  enqueue,
  drain,
  getQueue,
  type OfflineQueueItem,
  type DrainResult,
} from '../services/offline-queue/index';
import { useNetworkStatus } from './useNetworkStatus';

// =============================================================================
// Types
// =============================================================================

export type MutationExecutor = (item: OfflineQueueItem) => Promise<void>;

export interface UseOfflineMutationOptions {
  /** Async function that sends one queued item to the server. */
  executor: MutationExecutor;
  /** Called after a successful drain (at least one item succeeded). */
  onDrained?: (result: DrainResult) => void;
}

export interface UseOfflineMutationResult {
  /**
   * Enqueue a mutation for offline-safe execution.
   * If online, this will trigger an immediate drain attempt after enqueue.
   */
  enqueueMutation: (
    mutation: string,
    variables: Record<string, unknown>,
  ) => Promise<OfflineQueueItem>;
  /** True while the queue is draining. */
  isSyncing: boolean;
  /** Number of items currently waiting in the queue. */
  queueSize: number;
  /** Manually trigger a drain attempt. */
  drainNow: () => Promise<DrainResult>;
}

// =============================================================================
// Hook
// =============================================================================

/**
 * useOfflineMutation — offline-safe GraphQL mutation hook.
 *
 * @example
 * const { enqueueMutation, isSyncing, queueSize } = useOfflineMutation({
 *   executor: async (item) => {
 *     const result = await urqlClient.mutation(item.mutation, item.variables);
 *     if (result.error) throw result.error;
 *   },
 *   onDrained: ({ succeeded }) => console.log(`Synced ${succeeded.length} messages`),
 * });
 *
 * // On send:
 * await enqueueMutation(PERSIST_USER_MESSAGE, { content: text, conversationId });
 */
export function useOfflineMutation({
  executor,
  onDrained,
}: UseOfflineMutationOptions): UseOfflineMutationResult {
  const [isSyncing, setIsSyncing] = useState(false);
  const [queueSize, setQueueSize] = useState(0);
  const executorRef = useRef(executor);
  const onDrainedRef = useRef(onDrained);
  const { isOnline, onConnected } = useNetworkStatus();

  // Keep refs fresh without re-registering effects.
  executorRef.current = executor;
  onDrainedRef.current = onDrained;

  /** Refresh queue size counter. */
  const refreshQueueSize = useCallback(async () => {
    const items = await getQueue();
    setQueueSize(items.length);
  }, []);

  /** Run the drain cycle. */
  const drainNow = useCallback(async (): Promise<DrainResult> => {
    setIsSyncing(true);
    try {
      const result = await drain(executorRef.current);
      if (result.succeeded.length > 0) {
        onDrainedRef.current?.(result);
      }
      await refreshQueueSize();
      return result;
    } finally {
      setIsSyncing(false);
    }
  }, [refreshQueueSize]);

  /** Enqueue a mutation; trigger immediate drain if online. */
  const enqueueMutation = useCallback(
    async (
      mutation: string,
      variables: Record<string, unknown>,
    ): Promise<OfflineQueueItem> => {
      const item = await enqueue(mutation, variables);
      await refreshQueueSize();
      if (isOnline) {
        // Fire-and-forget drain on enqueue when online.
        void drainNow();
      }
      return item;
    },
    [isOnline, drainNow, refreshQueueSize],
  );

  // Subscribe to reconnect events — drain automatically on reconnect.
  useEffect(() => {
    const unsub = onConnected(() => {
      void drainNow();
    });
    return unsub;
  }, [onConnected, drainNow]);

  // Initialise queue size on mount.
  useEffect(() => {
    void refreshQueueSize();
  }, [refreshQueueSize]);

  return {
    enqueueMutation,
    isSyncing,
    queueSize,
    drainNow,
  };
}
