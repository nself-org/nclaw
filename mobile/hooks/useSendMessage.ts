/**
 * useSendMessage — orchestrate chat send: memory recall → ambient context → JSI chatSend → GraphQL persist.
 *
 * Purpose: Single hook that wires together:
 *   1. useMemoryRecall  — fetch relevant context before every send (T05).
 *   2. useAmbientContext — inject real-world sensor context block (T10).
 *   3. NativeNclaw.chatSend() via JSI — trigger Rust libnclaw inference (T03 + T04).
 *   4. GraphQL PersistUserMessage mutation — persist the user turn (T04).
 *   5. useMemoryInsert  — persist completed turn in the background (T05).
 *   6. Optimistic UI — message appears with 'sending' status immediately.
 *   7. Typed ChatError discriminated union — NetworkError, InferenceError, RateLimitError.
 *   8. Exponential-backoff retry on NetworkError (1 s, 2 s, 4 s, max 3 attempts).
 *
 * Inputs:
 *   conversationId     — ID of the current conversation; null to start a new one.
 *   model              — optional inference model name for memory insert metadata.
 *   ambientEnabled     — whether ambient sensor context should be injected (default false).
 *   onNewConversation  — called when chatSend() establishes a new conversationId.
 *   onOptimisticMessage — called immediately when user sends (optimistic insert).
 *   onMessageStatusChange — called when message transitions: sending → sent | failed.
 *
 * Outputs: { sendMessage, isSending, isRecalling, status, error, retryLast }
 *   sendMessage(text) — send a user message and trigger inference.
 *   isSending         — true while recall or chatSend or persist is in-flight.
 *   isRecalling       — true specifically while memory recall is running.
 *   status            — granular SendStatus for the most recent send.
 *   error             — typed ChatError or null; reset on next sendMessage.
 *   retryLast()       — re-attempt the last failed send.
 *
 * Constraints:
 *   - memoryRecall runs BEFORE chatSend; UI shows 'Recalling memory...' during this.
 *   - memoryInsert fires AFTER chatSend resolves — strictly non-blocking (no await).
 *   - A failed memoryRecall does NOT block the send — message is sent without context.
 *   - Ambient context appended as a separate system block after memory context.
 *   - No business logic in JSX — all orchestration lives in this hook.
 *   - GraphQL mutation uses urql useMutation (network-only) for offline queue support.
 *   - NcLawJSI.chatSend() is fully typed via @nself/native-bridge (added in T04).
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref:
 *   T-P3-E4-W2-S3-T03 (JSI bridge — NativeNclaw registration)
 *   T-P3-E4-W2-S3-T04 (this ticket — chatSend API, GraphQL persist, status transitions)
 *   T-P3-E4-W2-S3-T05 (memory hooks — useMemoryRecall, useMemoryInsert)
 *   T-P3-E4-W2-S3-T10 (ambient context — useAmbientContext)
 *   nclaw/mobile/services/chat.ts (GraphQL documents)
 */

import { useCallback, useRef, useState } from 'react';
import { useMutation } from 'urql';
import { NativeNclaw } from '@nself/native-bridge';

import { useMemoryRecall } from './useMemoryRecall';
import { useMemoryInsert } from './useMemoryInsert';
import { useAmbientContext } from './useAmbientContext';
import {
  PERSIST_USER_MESSAGE,
  OFFLINE_REQUEST_POLICY,
  type PersistUserMessageData,
  type PersistUserMessageVariables,
} from '../services/chat';
import type { ChatError, ChatMessage, MessageStatus } from '../types/chat';

// =============================================================================
// Constants
// =============================================================================

/** Maximum number of NetworkError retry attempts before escalating to 'failed'. */
const MAX_NETWORK_RETRIES = 3;

/** Initial backoff delay in milliseconds for exponential retry. */
const INITIAL_BACKOFF_MS = 1000;

// =============================================================================
// Types
// =============================================================================

/** Granular status including memory recall phase. */
export type SendStatus = 'idle' | 'recalling' | 'sending' | 'sent' | 'failed';

export interface UseSendMessageOptions {
  /**
   * ID of the conversation to continue. Pass null to start a new conversation.
   * The hook calls onNewConversation() when chatSend() returns a new conversationId.
   */
  conversationId: string | null;
  /**
   * Optional inference model name — stored in memory insert metadata.
   * Defaults to null (model chosen by libnclaw based on server config).
   */
  model?: string | null;
  /**
   * Whether ambient sensor context should be injected into the prompt (T10).
   * Defaults to false.
   */
  ambientEnabled?: boolean;
  /**
   * Invoked when chatSend() establishes a new conversationId (was null before).
   * The chat screen should update its state so subsequent sends continue this conversation.
   */
  onNewConversation?: (conversationId: string) => void;
  /**
   * Invoked when a new optimistic ChatMessage should be inserted at the top of the list.
   * Called immediately on send so the user sees their message without waiting for the server.
   */
  onOptimisticMessage?: (message: ChatMessage) => void;
  /**
   * Invoked when the status of an existing message changes: sending → sent | failed.
   * Caller matches on messageId and updates the list entry in-place.
   */
  onMessageStatusChange?: (messageId: string, status: MessageStatus) => void;
}

export interface UseSendMessageResult {
  /**
   * Send a message: recall context → augment → chatSend → persist → insert memory.
   * No-op while a send is already in-flight.
   */
  sendMessage: (text: string) => Promise<void>;
  /** True while recall or chatSend or persist is in-flight. */
  isSending: boolean;
  /** True specifically while memory recall is running (drives 'Recalling memory...' indicator). */
  isRecalling: boolean;
  /** Granular status for the most recent send operation. */
  status: SendStatus;
  /** Typed chat error or null. Reset to null on next sendMessage call. */
  error: ChatError | null;
  /** Re-attempt the last failed send. No-op when no prior send has failed. */
  retryLast: () => Promise<void>;
}

// =============================================================================
// Helpers
// =============================================================================

/** Sleep for `ms` milliseconds. Used for exponential-backoff retry. */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Classify an unknown thrown value into a typed ChatError discriminated union.
 *
 * Priority: RateLimitError > NetworkError > InferenceError.
 * All Rust FFI error messages propagate through the JSI promise rejection path.
 */
export function classifyChatError(err: unknown): ChatError {
  const message = err instanceof Error ? err.message : String(err);

  // Rate limit: Rust surfaces "rate_limit" or "rate limit" in the error string
  if (message.includes('rate_limit') || message.includes('rate limit')) {
    return {
      kind: 'RateLimitError',
      message: 'Too many requests. Please wait a moment before retrying.',
      retryAfterMs: 5000,
    };
  }

  // Network error: JSI bridge disconnected or Hasura unreachable
  if (
    message.includes('[Network]') ||
    message.includes('network') ||
    message.includes('ECONNREFUSED') ||
    message.includes('ETIMEDOUT') ||
    message.includes('fetch failed')
  ) {
    return {
      kind: 'NetworkError',
      message: 'No connection. Message will be sent when you are back online.',
    };
  }

  // All other failures: inference pipeline error
  const codeMatch = /code[:=]\s*(\w+)/i.exec(message);
  return {
    kind: 'InferenceError',
    message: message || 'Something went wrong with the AI response.',
    code: codeMatch?.[1] ?? 'unknown',
  };
}

/** Generate a v4-style UUID via Math.random (sufficient for optimistic IDs). */
export function generateId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// =============================================================================
// Hook
// =============================================================================

/**
 * useSendMessage — full-lifecycle AI chat send hook.
 *
 * Usage in chat.tsx:
 *   const { sendMessage, isSending, isRecalling, status, error, retryLast } =
 *     useSendMessage({
 *       conversationId,
 *       onNewConversation: setConversationId,
 *       onOptimisticMessage: (msg) => setMessages(prev => [msg, ...prev]),
 *       onMessageStatusChange: (id, s) =>
 *         setMessages(prev => prev.map(m => m.id === id ? { ...m, status: s } : m)),
 *     });
 */
export function useSendMessage({
  conversationId,
  model = null,
  ambientEnabled = false,
  onNewConversation,
  onOptimisticMessage,
  onMessageStatusChange,
}: UseSendMessageOptions): UseSendMessageResult {
  const [status, setStatus] = useState<SendStatus>('idle');
  const [error, setError] = useState<ChatError | null>(null);

  const { recallForQuery, isRecalling } = useMemoryRecall();
  const { insertMemory } = useMemoryInsert();
  const { getContextBlock } = useAmbientContext(ambientEnabled);

  // urql mutation — persist the user message turn with offline-queue support
  const [, persistUserMessage] = useMutation<PersistUserMessageData, PersistUserMessageVariables>(
    PERSIST_USER_MESSAGE,
  );

  // Track last send text and tempId for retryLast support
  const lastTextRef = useRef<string | null>(null);
  const lastTempIdRef = useRef<string | null>(null);

  // ─── Core send logic ─────────────────────────────────────────────────────

  const _doSend = useCallback(
    async (text: string, tempId: string, attempt: number): Promise<void> => {
      setError(null);

      // Step 1 — Recall memory context (non-fatal: send proceeds without context on error)
      setStatus('recalling');
      const memoryCtx = await recallForQuery(text);

      // Step 2 — Optimistic update on first attempt only
      if (attempt === 1) {
        const optimistic: ChatMessage = {
          id: tempId,
          role: 'user',
          content: text,
          createdAt: new Date().toISOString(),
          threadId: conversationId ?? '',
          status: 'sending',
          isStreaming: false,
        };
        onOptimisticMessage?.(optimistic);
      }

      // Step 3 — Augment prompt with memory context + ambient sensor context
      const parts: string[] = [];
      if (memoryCtx) parts.push(memoryCtx);
      const ambientBlock = getContextBlock();
      if (ambientBlock) {
        parts.push(`[system:ambient] ${JSON.stringify(ambientBlock)}`);
      }
      parts.push(text);
      const augmentedPrompt = parts.join('\n\n');

      // Step 4 — Establish conversationId (generate client-side if new conversation).
      //   NativeNclaw.chatSend() returns the full AI response string (T03 contract).
      //   The conversationId is managed here so the GraphQL subscription can be
      //   set up before chatSend() resolves (subscription starts in chat.tsx on conversationId change).
      const activeConversationId = conversationId ?? generateId();
      if (!conversationId && onNewConversation) {
        // Notify caller of the new conversationId immediately so the subscription starts
        onNewConversation(activeConversationId);
      }

      // Step 5 — JSI chatSend: trigger Rust libnclaw inference pipeline (T03: returns string)
      setStatus('sending');

      try {
        const aiResponse = await NativeNclaw.chatSend(augmentedPrompt);

        // Step 6 — GraphQL mutation: persist the user turn (offline-queued automatically)
        const messageId = generateId();
        const mutResult = await persistUserMessage(
          {
            conversationId: activeConversationId,
            messageId,
            content: text,
          },
          { requestPolicy: OFFLINE_REQUEST_POLICY },
        );

        if (mutResult.error) {
          // Treat GraphQL mutation error as network error for retry classification
          throw new Error(`[Network] GraphQL persist failed: ${mutResult.error.message}`);
        }

        // Step 7 — Status transition: sending → sent
        onMessageStatusChange?.(tempId, 'sent');
        setStatus('sent');

        // Step 8 — Fire-and-forget memory inserts (non-blocking, best-effort)
        insertMemory({
          conversationId: activeConversationId,
          role: 'user',
          content: text,
          model: null,
        });
        // Also insert the AI response turn so it appears in future memory context
        insertMemory({
          conversationId: activeConversationId,
          role: 'assistant',
          content: aiResponse,
          model: model ?? null,
        });
      } catch (err: unknown) {
        const chatError = classifyChatError(err);

        // NetworkError with retries remaining: exponential backoff + retry
        if (chatError.kind === 'NetworkError' && attempt < MAX_NETWORK_RETRIES) {
          const backoffMs = INITIAL_BACKOFF_MS * Math.pow(2, attempt - 1);
          await sleep(backoffMs);
          return _doSend(text, tempId, attempt + 1);
        }

        // All retries exhausted or non-network error: surface as 'failed'
        onMessageStatusChange?.(tempId, 'failed');
        setError(chatError);
        setStatus('failed');
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      conversationId,
      model,
      recallForQuery,
      insertMemory,
      getContextBlock,
      persistUserMessage,
      onNewConversation,
      onOptimisticMessage,
      onMessageStatusChange,
    ],
  );

  // ─── Public API ──────────────────────────────────────────────────────────

  const sendMessage = useCallback(
    async (text: string): Promise<void> => {
      // Guard: no concurrent sends while one is in-flight
      if (status === 'recalling' || status === 'sending') return;
      const trimmed = text.trim();
      if (!trimmed) return;

      const tempId = generateId();
      lastTextRef.current = trimmed;
      lastTempIdRef.current = tempId;
      await _doSend(trimmed, tempId, 1);
    },
    [status, _doSend],
  );

  const retryLast = useCallback(async (): Promise<void> => {
    if (!lastTextRef.current || !lastTempIdRef.current) return;
    await _doSend(lastTextRef.current, lastTempIdRef.current, 1);
  }, [_doSend]);

  return {
    sendMessage,
    isSending: status === 'recalling' || status === 'sending',
    isRecalling,
    status,
    error,
    retryLast,
  };
}
