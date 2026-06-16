import type { Conversation } from '@/types';
import api from '@/lib/api';

/** Maximum number of untitled conversations to backfill in one pass. */
const BACKFILL_LIMIT = 77;

/**
 * Generates a date-based fallback title for a conversation.
 * Format: "Chat, Apr 18"
 */
export function fallbackTitle(conversation: { createdAt: string }): string {
  const date = new Date(conversation.createdAt);
  const formatted = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
  }).format(date);
  return `Chat, ${formatted}`;
}

/** Returns true when a conversation has no meaningful title. */
function isUntitled(title: string | null | undefined): boolean {
  if (!title) return true;
  const normalized = title.trim().toLowerCase();
  return normalized === '' || normalized === 'untitled';
}

/**
 * Backfills titles for up to 77 untitled conversations.
 *
 * Strategy:
 * 1. Attempts api.backfillUntitledTitles() for a server-side AI-generated pass.
 * 2. If the API call fails, applies date-based fallbackTitle() locally via updateConversation.
 *
 * Returns a summary of { updated, skipped, fallbackApplied }.
 */
export async function backfillUntitledSessions(
  conversations: Conversation[],
  updateConversation: (id: string, updates: Partial<Conversation>) => void,
): Promise<{ updated: number; skipped: number; fallbackApplied: number }> {
  const untitled = conversations
    .filter((c) => isUntitled(c.title))
    .slice(0, BACKFILL_LIMIT);

  if (untitled.length === 0) {
    return { updated: 0, skipped: 0, fallbackApplied: 0 };
  }

  // Attempt server-side backfill first.
  const backfillResult = await api.backfillUntitledTitles();
  if (backfillResult.ok) {
    return {
      updated: backfillResult.value.updated,
      skipped: backfillResult.value.skipped,
      fallbackApplied: 0,
    };
  }

  // Server backfill failed — apply local date-based fallback titles.
  for (const conv of untitled) {
    updateConversation(conv.id, { title: fallbackTitle(conv) });
  }
  return { updated: 0, skipped: 0, fallbackApplied: untitled.length };
}
