/**
 * useMemoryRecall — retrieve relevant memory context before each chat send.
 *
 * Purpose: Calls NativeNclaw.memorySearch() via the @nself/native-bridge JSI seam
 *          to fetch up to 5 Memory results semantically similar to the user's query.
 *          Results are formatted as a system-context block for injection into the
 *          inference prompt by useSendMessage.
 *
 * Inputs:  query — the user's message text (used as the semantic search string).
 * Outputs: { recall, isRecalling, error } — recall is the formatted context string
 *          or null when no memories match; isRecalling is true while the async call
 *          is in flight (drives the 'Recalling memory...' UX indicator).
 *
 * Constraints: Must not block the JS thread. memorySearch is dispatched via JSI
 *              promise and the hook exposes isRecalling so the UI can show an
 *              indicator without delaying the send action.
 *              Returns at most MEMORY_RECALL_LIMIT (5) results.
 *              Never throws — errors are captured and surfaced via the error field.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T03 (NativeNclaw JSI bridge), T-P3-E4-W2-S3-T04 (useSendMessage).
 */

import { useCallback, useState } from 'react';
import { getNcLawJSI, type Memory } from '@nself/native-bridge';

/** Maximum number of memory results to retrieve per recall. */
const MEMORY_RECALL_LIMIT = 5;

/**
 * Format a list of Memory objects into a system-context block that can be
 * prepended to the inference prompt. Returns null when memories is empty.
 */
function formatMemoryContext(memories: Memory[]): string | null {
  if (memories.length === 0) return null;
  const lines = memories.map((m, i) => `[${i + 1}] (${m.memoryType}) ${m.content}`);
  return `<memory_context>\n${lines.join('\n')}\n</memory_context>`;
}

export interface UseMemoryRecallResult {
  /** Formatted memory context string, or null when no memories found. */
  recall: string | null;
  /** True while memorySearch is in-flight (drives 'Recalling memory...' indicator). */
  isRecalling: boolean;
  /** Non-null when memorySearch threw; the chat send is NOT blocked by this error. */
  error: Error | null;
  /**
   * Execute a memory recall for the given query.
   * Returns the formatted context string (or null) and resolves after memorySearch
   * completes. Callers should await this before constructing the final prompt.
   */
  recallForQuery: (query: string) => Promise<string | null>;
}

/**
 * Hook: call memorySearch before each chat send and expose a formatted context block.
 *
 * Usage in useSendMessage:
 *   const { recallForQuery, isRecalling } = useMemoryRecall();
 *   const ctx = await recallForQuery(message);
 *   const prompt = ctx ? `${ctx}\n\n${message}` : message;
 */
export function useMemoryRecall(): UseMemoryRecallResult {
  const [recall, setRecall] = useState<string | null>(null);
  const [isRecalling, setIsRecalling] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const recallForQuery = useCallback(async (query: string): Promise<string | null> => {
    setIsRecalling(true);
    setError(null);
    try {
      const jsi = getNcLawJSI();
      const memories = await jsi.memorySearch(query, MEMORY_RECALL_LIMIT);
      const ctx = formatMemoryContext(memories);
      setRecall(ctx);
      return ctx;
    } catch (err) {
      const e = err instanceof Error ? err : new Error(String(err));
      setError(e);
      setRecall(null);
      return null;
    } finally {
      setIsRecalling(false);
    }
  }, []);

  return { recall, isRecalling, error, recallForQuery };
}
