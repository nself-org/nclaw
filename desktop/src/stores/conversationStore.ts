// ɳClaw Desktop — Conversation store (Zustand + pglite IPC client)
//
// Tracks recent conversations loaded from the embedded-PG backend via the
// `getPgliteClient()` IPC client. Components consume this store instead of
// calling the Tauri IPC layer directly.
//
// When the backend is not yet available (embedded-PG not started, or S17 DB
// commands returning NotImplemented), `conversations` is an empty array and
// `loading` is false — the UI renders empty state cleanly.
//
// Usage:
//   const { conversations, loadRecentConversations } = useConversationStore();
//
//   // Mount once at app init:
//   useEffect(() => { loadRecentConversations(); }, []);

import { create } from "zustand";
import { getPgliteClient, type Conversation } from "../lib/pglite/client";
import type { PaletteResult } from "../lib/palette-actions";

// ---- Types ------------------------------------------------------------------

export interface ConversationState {
  /** The N most recently updated conversations. Empty array until loaded. */
  conversations: Conversation[];

  /** True while the IPC call is in-flight. */
  loading: boolean;

  /** Error from the most recent load attempt, or null. */
  error: string | null;

  // ---- Actions --------------------------------------------------------------

  /**
   * Load (or reload) the N most recent conversations from the embedded-PG
   * backend. Resets `error` on each call.
   *
   * @param limit - Max conversations to return (default: 10).
   */
  loadRecentConversations(limit?: number): Promise<void>;

  /**
   * Convert the current `conversations` list to `PaletteResult[]` for use
   * inside `CommandPalette`. Pure transform — no side effects.
   */
  toPaletteResults(): PaletteResult[];
}

// ---- Store ------------------------------------------------------------------

export const useConversationStore = create<ConversationState>((set, get) => ({
  conversations: [],
  loading: false,
  error: null,

  loadRecentConversations: async (limit = 10) => {
    set({ loading: true, error: null });
    try {
      const client = getPgliteClient();
      const conversations = await client.listRecentConversations(limit);
      set({ conversations, loading: false });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      set({ conversations: [], loading: false, error: msg });
    }
  },

  toPaletteResults: (): PaletteResult[] => {
    return get().conversations.map((conv) => ({
      kind: "conversation" as const,
      id: conv.id,
      label: conv.title,
      description: conv.summary ?? conv.topicPath ?? undefined,
    }));
  },
}));
