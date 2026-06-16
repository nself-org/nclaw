'use client';

import { useEffect, useRef } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api from '@/lib/api';
import { type ClawError, networkError } from '@/lib/result';
import { useChatStore } from '@/store/chat-store';
import { backfillUntitledSessions } from '@/lib/session-titler';
import type { Conversation } from '@/types';

const CONVERSATIONS_KEY = ['conversations'] as const;

/**
 * Hook for session (conversation) management.
 *
 * Purpose: Fetches, creates, and deletes conversations; syncs with Zustand store.
 *
 * - Fetches the full conversations list via TanStack Query.
 * - Syncs the result into the Zustand chat store.
 * - Auto-backfills untitled sessions once per mount.
 * - Exposes createConversation and deleteConversation mutations.
 *
 * Inputs:  None (reads auth token from ApiClient internally).
 * Outputs: { conversations, isLoading, error, createConversation, deleteConversation }
 *
 * Constraints:
 *   - error field is ClawError | null — no untyped throws exposed to callers.
 *   - Mutations surface typed ClawError via thrown errors with attached clawError prop
 *     (TanStack Query useMutation contract).
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */
export function useSessions(): {
  conversations: Conversation[];
  isLoading: boolean;
  error: ClawError | null;
  createConversation: (topicId?: string) => Promise<Conversation>;
  deleteConversation: (id: string) => Promise<void>;
} {
  const queryClient = useQueryClient();

  const setConversations = useChatStore((s) => s.setConversations);
  const addConversation = useChatStore((s) => s.addConversation);
  const removeConversation = useChatStore((s) => s.removeConversation);
  const updateConversation = useChatStore((s) => s.updateConversation);
  const storeConversations = useChatStore((s) => s.conversations);

  // Track whether the backfill has already been attempted this mount.
  const backfillDoneRef = useRef(false);

  const { data, isLoading, error: queryError } = useQuery({
    queryKey: CONVERSATIONS_KEY,
    queryFn: async () => {
      const result = await api.listConversations(1, 200);
      if (!result.ok) {
        // TanStack Query expects a throw; attach typed error for callers.
        throw Object.assign(new Error(result.error.message), {
          clawError: result.error,
        });
      }
      return result.value.data;
    },
    staleTime: 30_000,
  });

  // Extract the typed ClawError from the query error if present.
  const queryClawError: ClawError | null = queryError
    ? ((queryError as { clawError?: ClawError }).clawError ??
      networkError(queryError))
    : null;

  // Keep store in sync whenever query data changes.
  useEffect(() => {
    if (data) {
      setConversations(data);
    }
  }, [data, setConversations]);

  // Backfill untitled sessions once after the first successful fetch.
  useEffect(() => {
    if (!data || backfillDoneRef.current) return;
    backfillDoneRef.current = true;

    void backfillUntitledSessions(data, updateConversation);
  }, [data, updateConversation]);

  const createMutation = useMutation({
    mutationFn: async (topicId?: string) => {
      const result = await api.createConversation(topicId);
      if (!result.ok) {
        throw Object.assign(new Error(result.error.message), {
          clawError: result.error,
        });
      }
      return result.value;
    },
    onSuccess: (conv) => {
      addConversation(conv);
      void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      const result = await api.deleteConversation(id);
      if (!result.ok) {
        throw Object.assign(new Error(result.error.message), {
          clawError: result.error,
        });
      }
    },
    onSuccess: (_data, id) => {
      removeConversation(id);
      void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
    },
  });

  const createConversation = async (topicId?: string): Promise<Conversation> => {
    return createMutation.mutateAsync(topicId);
  };

  const deleteConversation = async (id: string): Promise<void> => {
    await deleteMutation.mutateAsync(id);
  };

  return {
    conversations: storeConversations,
    isLoading,
    error: queryClawError,
    createConversation,
    deleteConversation,
  };
}

export default useSessions;
