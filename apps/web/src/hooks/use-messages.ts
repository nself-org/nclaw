'use client';

import { useCallback, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import api from '@/lib/api';
import { type ClawError, networkError } from '@/lib/result';
import { useChatStore } from '@/store/chat-store';
import type { Message, SendMessageRequest } from '@/types';

function messagesKey(conversationId: string) {
  return ['messages', conversationId] as const;
}

/**
 * Hook for message management within a single conversation.
 *
 * Purpose: Fetches, streams, and manages chat messages for a conversation.
 *
 * - Fetches the message list for conversationId via TanStack Query.
 * - Syncs fetched messages into the Zustand chat store.
 * - Manages streaming state: opens a ReadableStream, appends deltas incrementally.
 * - Exposes sendMessage (initiates a stream) and stopStream (aborts it).
 * - Optimistic update on sendMessage: appends user + assistant placeholder immediately.
 *   On stream failure, BOTH optimistic messages are removed and onSendError fires
 *   so the caller can show a toast / retry UI. The rollback uses IDs assigned at
 *   send time so there is no ambiguity with server-confirmed messages.
 *
 * Inputs:
 *   conversationId — string, must be non-empty to enable the query
 *   onSendError    — optional callback invoked with a typed ClawError on rollback
 *
 * Outputs: { messages, isLoading, error, sendMessage, isStreaming, stopStream }
 *
 * Constraints:
 *   - error field is ClawError | null — never a raw Error (no untyped throws).
 *   - Optimistic IDs use `local-*` prefix; they never collide with server UUIDs.
 *   - Rollback removes the optimistic items by ID; existing server messages are
 *     preserved.
 *   - Only one stream is active at a time (guarded by isStreaming).
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */
export function useMessages(
  conversationId: string,
  options?: { onSendError?: (clawError: ClawError) => void },
): {
  messages: Message[];
  isLoading: boolean;
  error: ClawError | null;
  sendMessage: (content: string, topicId?: string | null) => Promise<void>;
  isStreaming: boolean;
  stopStream: () => void;
} {
  const queryClient = useQueryClient();
  const onSendError = options?.onSendError;

  const setMessages = useChatStore((s) => s.setMessages);
  const appendMessage = useChatStore((s) => s.appendMessage);
  const appendStreamingContent = useChatStore((s) => s.appendStreamingContent);
  const clearStreamingContent = useChatStore((s) => s.clearStreamingContent);
  const storeMessages = useChatStore((s) => s.messages[conversationId] ?? []);

  const [isStreaming, setIsStreaming] = useState(false);
  const [sendError, setSendError] = useState<ClawError | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const { isLoading, error: queryError } = useQuery({
    queryKey: messagesKey(conversationId),
    queryFn: async () => {
      const result = await api.listMessages(conversationId);
      if (!result.ok) {
        // TanStack Query expects a throw to mark the query as errored.
        // We attach the typed ClawError so the error field carries it.
        const e = Object.assign(new Error(result.error.message), {
          clawError: result.error,
        });
        throw e;
      }
      return result.value.data;
    },
    staleTime: 10_000,
    enabled: conversationId.length > 0,
    // Sync into Zustand on each successful fetch.
    select: (data: Message[]) => {
      setMessages(conversationId, data);
      return data;
    },
  });

  // Extract the typed ClawError from the query error if present.
  const queryClawError: ClawError | null = queryError
    ? ((queryError as { clawError?: ClawError }).clawError ??
      networkError(queryError))
    : null;

  const stopStream = useCallback(() => {
    abortRef.current?.abort();
    setIsStreaming(false);
    clearStreamingContent();
  }, [clearStreamingContent]);

  const sendMessage = useCallback(
    async (content: string, topicId?: string | null): Promise<void> => {
      if (!content.trim() || isStreaming) return;
      setSendError(null);

      // Use a stable timestamp prefix so both IDs share the same instant.
      const ts = Date.now();
      const userMsgId = `local-user-${ts}`;
      const assistantMsgId = `local-assistant-${ts}`;

      // Optimistically append the user message.
      const userMsg: Message = {
        id: userMsgId,
        conversationId,
        role: 'user',
        content: content.trim(),
        createdAt: new Date(ts).toISOString(),
        tokens: null,
      };
      appendMessage(userMsg);

      // Placeholder assistant message for streaming.
      const assistantMsg: Message = {
        id: assistantMsgId,
        conversationId,
        role: 'assistant',
        content: '',
        createdAt: new Date(ts).toISOString(),
        tokens: null,
      };
      appendMessage(assistantMsg);

      clearStreamingContent();
      setIsStreaming(true);

      const req: SendMessageRequest = {
        conversationId,
        content: content.trim(),
        topicId: topicId ?? null,
      };

      const abort = new AbortController();
      abortRef.current = abort;

      let succeeded = false;

      // sendMessageRaw returns Result — no throws needed.
      const streamResult = await api.sendMessageRaw(req);

      if (!streamResult.ok) {
        // Rollback optimistic messages.
        const current =
          useChatStore.getState().messages[conversationId] ?? [];
        setMessages(
          conversationId,
          current.filter(
            (m) => m.id !== userMsgId && m.id !== assistantMsgId
          ),
        );
        setSendError(streamResult.error);
        onSendError?.(streamResult.error);
        setIsStreaming(false);
        clearStreamingContent();
        abortRef.current = null;
        return;
      }

      const reader = streamResult.value.getReader();
      let accumulated = '';

      try {
        while (true) {
          if (abort.signal.aborted) break;

          const { done, value } = await reader.read();
          if (done) break;

          if (value.type === 'delta' && value.content) {
            accumulated += value.content;
            appendStreamingContent(value.content);

            // Patch the in-progress assistant message with accumulated content.
            const current =
              useChatStore.getState().messages[conversationId] ?? [];
            setMessages(conversationId, [
              ...current.filter((m) => m.id !== assistantMsgId),
              { ...assistantMsg, content: accumulated },
            ]);
          }
        }

        succeeded = true;
      } catch (e) {
        // Rollback: remove both optimistic messages entirely.
        const current =
          useChatStore.getState().messages[conversationId] ?? [];
        setMessages(
          conversationId,
          current.filter(
            (m) => m.id !== userMsgId && m.id !== assistantMsgId
          ),
        );
        const clawErr = networkError(e);
        setSendError(clawErr);
        onSendError?.(clawErr);
      } finally {
        setIsStreaming(false);
        clearStreamingContent();
        abortRef.current = null;

        if (succeeded) {
          // Invalidate so the next focus refreshes confirmed messages from server.
          void queryClient.invalidateQueries({
            queryKey: messagesKey(conversationId),
          });
        }
      }
    },
    [
      conversationId,
      isStreaming,
      appendMessage,
      appendStreamingContent,
      clearStreamingContent,
      setMessages,
      queryClient,
      onSendError,
    ],
  );

  return {
    messages: storeMessages,
    isLoading,
    error: queryClawError ?? sendError,
    sendMessage,
    isStreaming,
    stopStream,
  };
}

export default useMessages;
