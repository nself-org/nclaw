// ɳClaw Desktop — Backend store (Zustand + Tauri invoke bridge)
//
// Tracks the lifecycle of the embedded-PG backend that is launched via
// `commands::backend::start_embedded_pg` (S17). The frontend can bind
// reactive components against `useBackendStore()` to show:
//   - whether embedded-PG is available
//   - whether it is currently starting
//   - the most recent result / error from the last start attempt
//   - a live log of lines emitted by the CLI subprocess
//
// Usage:
//   const { embeddedPgActive, startEmbeddedPg } = useBackendStore();

import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

// ---- Types ------------------------------------------------------------------

/** Mirror of the Rust `EmbeddedPgResult` returned by `start_embedded_pg`. */
export interface EmbeddedPgResult {
  ok: boolean;
  exitCode: number;
  message: string;
}

export interface BackendState {
  /** true while `start_embedded_pg` is in-flight. */
  embeddedPgStarting: boolean;

  /**
   * true after a successful `start_embedded_pg` call (exitCode === 0).
   * Reset to false when `reset()` is called or on app startup.
   */
  embeddedPgActive: boolean;

  /** Result from the most recent `startEmbeddedPg()` call. null before first call. */
  embeddedPgResult: EmbeddedPgResult | null;

  /** Error message from the most recent failed call. null on success or before first call. */
  embeddedPgError: string | null;

  /**
   * Live log lines streamed from the CLI subprocess via the `backend://log` event.
   * Capped at MAX_LOG_LINES to prevent unbounded growth.
   */
  embeddedPgLog: string[];

  // ---- Actions --------------------------------------------------------------

  /** Invoke `start_embedded_pg` on the Rust side and update state. */
  startEmbeddedPg: () => Promise<void>;

  /** Append a log line (called by the event listener set up in `listenBackendLog`). */
  appendLog: (line: string) => void;

  /** Clear log and reset result state — call before each fresh start attempt. */
  reset: () => void;
}

// Maximum number of log lines retained in memory.
const MAX_LOG_LINES = 1_000;

// ---- Store ------------------------------------------------------------------

export const useBackendStore = create<BackendState>((set, get) => ({
  embeddedPgStarting: false,
  embeddedPgActive: false,
  embeddedPgResult: null,
  embeddedPgError: null,
  embeddedPgLog: [],

  startEmbeddedPg: async () => {
    if (get().embeddedPgStarting) {
      return; // already in flight — no double-start
    }

    set({
      embeddedPgStarting: true,
      embeddedPgResult: null,
      embeddedPgError: null,
      embeddedPgLog: [],
    });

    try {
      const result = await invoke<EmbeddedPgResult>("start_embedded_pg");
      set({
        embeddedPgStarting: false,
        embeddedPgActive: result.ok,
        embeddedPgResult: result,
        embeddedPgError: result.ok ? null : result.message,
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      set({
        embeddedPgStarting: false,
        embeddedPgActive: false,
        embeddedPgResult: { ok: false, exitCode: -1, message: msg },
        embeddedPgError: msg,
      });
    }
  },

  appendLog: (line: string) => {
    set((state) => ({
      embeddedPgLog:
        state.embeddedPgLog.length >= MAX_LOG_LINES
          ? [...state.embeddedPgLog.slice(1), line]
          : [...state.embeddedPgLog, line],
    }));
  },

  reset: () => {
    set({
      embeddedPgStarting: false,
      embeddedPgActive: false,
      embeddedPgResult: null,
      embeddedPgError: null,
      embeddedPgLog: [],
    });
  },
}));

// ---- Event listener ---------------------------------------------------------

/**
 * Subscribe to `backend://log` events emitted by the Rust subprocess stream.
 * Returns an `unlistenFn` that the caller should invoke on cleanup.
 *
 * Call this once at app startup (e.g. in a top-level `useEffect`):
 * ```ts
 * useEffect(() => {
 *   let unlisten: UnlistenFn | undefined;
 *   listenBackendLog().then(fn => { unlisten = fn; });
 *   return () => { unlisten?.(); };
 * }, []);
 * ```
 */
export async function listenBackendLog(): Promise<UnlistenFn> {
  const { appendLog } = useBackendStore.getState();
  return listen<string>("backend://log", (event) => {
    appendLog(event.payload);
  });
}
