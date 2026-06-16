/**
 * offline-cache.ts
 *
 * Purpose: Persist the last 50 conversations (with their messages) in
 *          IndexedDB so claw-web can render /history while offline.
 *
 * Inputs:  Conversation + Message arrays from the API layer.
 * Outputs: Reads return CachedConversation[]; writes return void.
 *
 * Constraints:
 *  - Schema is versioned (DB_VERSION bump triggers upgrade path).
 *  - TTL is 24 h — stale entries are not served, only displayed with a banner.
 *  - Runs client-side only; guards against SSR via typeof window check.
 *
 * SPORT: offline cache feature — see REGISTRY-WEB-SURFACES.md nclaw claw-web row.
 */

import type { CachedConversation, Conversation, Message } from '@/types';

const DB_NAME = 'nclaw-offline';
const DB_VERSION = 1;
const STORE_CONVS = 'conversations';
const MAX_CACHED = 50;
const TTL_MS = 24 * 60 * 60 * 1000; // 24 h

// ---------------------------------------------------------------------------
// DB open
// ---------------------------------------------------------------------------

let _db: IDBDatabase | null = null;

function openDb(): Promise<IDBDatabase> {
  if (_db) return Promise.resolve(_db);
  if (typeof window === 'undefined') return Promise.reject(new Error('SSR'));

  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);

    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_CONVS)) {
        db.createObjectStore(STORE_CONVS, { keyPath: 'id' });
      }
    };

    req.onsuccess = () => {
      _db = req.result;
      resolve(req.result);
    };

    req.onerror = () => reject(req.error);
  });
}

// ---------------------------------------------------------------------------
// Write
// ---------------------------------------------------------------------------

/**
 * Persist up to MAX_CACHED conversations (sorted by lastMessageAt desc).
 * Messages for each conversation must be supplied separately.
 */
export async function cacheConversations(
  conversations: Conversation[],
  messagesMap: Record<string, Message[]>
): Promise<void> {
  const db = await openDb();
  const sorted = [...conversations]
    .sort((a, b) => {
      const ta = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : 0;
      const tb = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : 0;
      return tb - ta;
    })
    .slice(0, MAX_CACHED);

  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_CONVS, 'readwrite');
    const store = tx.objectStore(STORE_CONVS);

    for (const conv of sorted) {
      const row: CachedConversation = {
        id: conv.id,
        title: conv.title,
        topicId: conv.topicId,
        updatedAt: conv.updatedAt,
        lastMessageAt: conv.lastMessageAt,
        messageCount: conv.messageCount,
        messages: messagesMap[conv.id] ?? [],
        cachedAt: Date.now(),
      };
      store.put(row);
    }

    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

/**
 * Cache a single conversation's messages (called after a chat load).
 */
export async function cacheConversationMessages(
  conv: Conversation,
  messages: Message[]
): Promise<void> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_CONVS, 'readwrite');
    const store = tx.objectStore(STORE_CONVS);
    const getReq = store.get(conv.id);

    getReq.onsuccess = () => {
      const existing = getReq.result as CachedConversation | undefined;
      const row: CachedConversation = {
        id: conv.id,
        title: conv.title,
        topicId: conv.topicId,
        updatedAt: conv.updatedAt,
        lastMessageAt: conv.lastMessageAt,
        messageCount: conv.messageCount,
        messages,
        cachedAt: existing?.cachedAt ?? Date.now(),
      };
      store.put(row);
    };

    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

// ---------------------------------------------------------------------------
// Read
// ---------------------------------------------------------------------------

/**
 * Return all cached conversations, newest first.
 * Returns empty array if IndexedDB is unavailable or all entries are stale.
 */
export async function readCachedConversations(): Promise<CachedConversation[]> {
  try {
    const db = await openDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_CONVS, 'readonly');
      const store = tx.objectStore(STORE_CONVS);
      const req = store.getAll();

      req.onsuccess = () => {
        const all = (req.result as CachedConversation[]).filter(
          (r) => Date.now() - r.cachedAt < TTL_MS
        );
        all.sort((a, b) => {
          const ta = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : 0;
          const tb = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : 0;
          return tb - ta;
        });
        resolve(all);
      };

      req.onerror = () => reject(req.error);
    });
  } catch {
    return [];
  }
}

/**
 * Return cached messages for a single conversation, or null if not cached.
 */
export async function readCachedMessages(conversationId: string): Promise<Message[] | null> {
  try {
    const db = await openDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_CONVS, 'readonly');
      const store = tx.objectStore(STORE_CONVS);
      const req = store.get(conversationId);

      req.onsuccess = () => {
        const row = req.result as CachedConversation | undefined;
        if (!row || Date.now() - row.cachedAt >= TTL_MS) {
          resolve(null);
        } else {
          resolve(row.messages);
        }
      };

      req.onerror = () => reject(req.error);
    });
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** True when the browser reports no network connection. */
export function isOffline(): boolean {
  return typeof navigator !== 'undefined' && !navigator.onLine;
}
