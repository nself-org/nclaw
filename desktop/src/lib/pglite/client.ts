// ɳClaw Desktop — pglite IPC client (S17)
//
// This module provides a typed interface for querying the embedded-PG backend
// that runs inside the nSelf CLI (via pglite/wasmtime). The desktop renderer
// process communicates with it through Tauri IPC commands, NOT through a
// direct pglite connection. The nSelf CLI hosts pglite and exposes results
// via Tauri commands registered in commands/topics.rs, commands/palette.rs, etc.
//
// Why not import @electric-sql/pglite in the renderer?
//   - pglite WASM runs inside the CLI process (Go + wasmtime). The CLI owns
//     the AF_UNIX socket bridge and the WASM lifecycle.
//   - The Tauri renderer (Vite + React) is a web context that cannot load
//     native binaries or heavy WASM modules without a bundler transformation
//     and explicit CSP allow-list. The pglite WASM binary is ~5 MB and
//     compiled by wasmtime to native code — not designed for browser embedding.
//   - CLI-first hard rule (nSelf PPI): all backend ops go through the nSelf
//     CLI. The renderer calls Tauri commands; the Rust shell calls the CLI.
//
// Usage example:
//   const client = getPgliteClient();
//   const convs = await client.listRecentConversations(10);

import { invoke } from "@tauri-apps/api/core";

// ---- Types ------------------------------------------------------------------

/** A conversation entry as returned by the embedded-PG-backed store. */
export interface Conversation {
  id: string;
  title: string;
  summary: string | null;
  /** ISO-8601 timestamp of the most recent message in this conversation. */
  updatedAt: string;
  /** Topic path this conversation belongs to (ltree notation, e.g. "work.ai"). */
  topicPath: string | null;
}

/** A lightweight topic entry for UI display. */
export interface Topic {
  id: string;
  path: string;
  name: string;
  archived: boolean;
}

// ---- Client -----------------------------------------------------------------

export interface PgliteClient {
  /**
   * Return the N most recently updated conversations, ordered by `updatedAt`
   * descending. Returns an empty array when the backend is not yet available.
   */
  listRecentConversations(limit: number): Promise<Conversation[]>;

  /**
   * Return all non-archived topics ordered by ltree path.
   * Returns an empty array when the backend is not yet available.
   */
  listTopics(): Promise<Topic[]>;
}

// Shared singleton — created once, reused across the app.
let _client: PgliteClient | null = null;

/**
 * Return the shared `PgliteClient` singleton.
 * Safe to call many times — only one instance is created.
 */
export function getPgliteClient(): PgliteClient {
  if (_client) return _client;

  _client = {
    async listRecentConversations(limit: number): Promise<Conversation[]> {
      try {
        // The Tauri side queries the embedded-PG backend via the Unix socket.
        // When the backend returns NotImplemented (S17 DB not yet wired),
        // we catch and return [].
        const results = await invoke<Conversation[]>(
          "list_recent_conversations",
          { limit }
        );
        return results;
      } catch (err: unknown) {
        // NotImplemented or backend unavailable — return empty list gracefully.
        if (isNotImplemented(err)) {
          return [];
        }
        console.warn("[pglite-client] listRecentConversations:", err);
        return [];
      }
    },

    async listTopics(): Promise<Topic[]> {
      try {
        const results = await invoke<Topic[]>("list_topics");
        return results;
      } catch (err: unknown) {
        if (isNotImplemented(err)) {
          return [];
        }
        console.warn("[pglite-client] listTopics:", err);
        return [];
      }
    },
  };

  return _client;
}

// ---- Helpers ----------------------------------------------------------------

/**
 * True when the Tauri command returned the canonical `NotImplemented` error
 * shape: `{ "error": "NotImplemented", "awaiting": "..." }`.
 */
function isNotImplemented(err: unknown): boolean {
  if (typeof err !== "string") return false;
  try {
    const parsed: unknown = JSON.parse(err);
    return (
      typeof parsed === "object" &&
      parsed !== null &&
      "error" in parsed &&
      (parsed as Record<string, unknown>)["error"] === "NotImplemented"
    );
  } catch {
    return false;
  }
}
