/**
 * useMemoryInsert — persist a conversation turn into libnclaw's memory store.
 *
 * Purpose: After each chat turn resolves, fires NativeNclaw.memoryInsert() via the
 *          @nself/native-bridge JSI seam to extract and persist facts, preferences,
 *          and events. The insert is strictly non-blocking — it runs in the background
 *          after the chat response is already delivered to the user.
 *
 * Inputs:  turn — a MemoryInsertTurn (conversationId, role, content, model).
 * Outputs: { insertMemory, isInserting, error } — insertMemory fires-and-forgets;
 *          it MUST NOT be awaited in the chat send flow (see Constraints).
 *
 * Constraints:
 *   - insertMemory() returns void immediately; the JSI promise runs in the background.
 *   - The chat response time MUST NOT be affected by this insert.
 *   - Errors are captured and surfaced via the error field; they do not rethrow.
 *   - If insertMemory is called while a prior insert is still in-flight, both proceed
 *     concurrently — no serialization is enforced here (Rust side is thread-safe).
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T03 (NativeNclaw JSI bridge), T-P3-E4-W2-S3-T04 (useSendMessage).
 */

import { useCallback, useState } from 'react';
import { getNcLawJSI, type MemoryInsertTurn } from '@nself/native-bridge';

export interface UseMemoryInsertResult {
  /**
   * Fire-and-forget: enqueue a memory insert for the given turn.
   * Do NOT await this in the chat send critical path — call it after the
   * response is already delivered so the user sees no latency.
   */
  insertMemory: (turn: MemoryInsertTurn) => void;
  /** True while memoryInsert is in-flight (informational only — not a blocker). */
  isInserting: boolean;
  /** Non-null when the most recent insert threw; prior inserts are unaffected. */
  error: Error | null;
}

/**
 * Hook: fire-and-forget memory insert after each conversation turn.
 *
 * Usage in useSendMessage (after response delivered):
 *   const { insertMemory } = useMemoryInsert();
 *   // Do NOT await — runs in background
 *   insertMemory({ conversationId, role: 'user', content: message, model: null });
 *   insertMemory({ conversationId, role: 'assistant', content: response, model });
 */
export function useMemoryInsert(): UseMemoryInsertResult {
  const [isInserting, setIsInserting] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const insertMemory = useCallback((turn: MemoryInsertTurn): void => {
    // Intentionally NOT returning the promise — fire-and-forget.
    setIsInserting(true);
    setError(null);

    getNcLawJSI()
      .memoryInsert(turn)
      .catch((err: unknown) => {
        const e = err instanceof Error ? err : new Error(String(err));
        setError(e);
      })
      .finally(() => {
        setIsInserting(false);
      });
  }, []);

  return { insertMemory, isInserting, error };
}
