'use client';

/**
 * /history — Conversation history with cursor-paginated message list.
 *
 * Purpose: Lists all conversations with a "Load more" CTA backed by usePagination.
 *          Each page fetches 20 items via the /claw/conversations?cursor= endpoint.
 *          AsyncScreen handles all 7 UI states; skeleton matches the populated list layout.
 *          When offline, falls back to IndexedDB-cached conversations (last 50, 24h TTL)
 *          and shows a stale banner. On reconnect the list auto-refreshes.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: edge-case resilience + offline cache
 */

import React, { useCallback, useEffect, useState } from 'react';
import { usePagination } from '@/hooks/use-pagination';
import { AsyncScreen } from '@/components/ui/AsyncScreen';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { Skeleton } from '@/components/ui/Skeleton';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import api from '@/lib/api';
import { getClawErrorMessage } from '@/lib/result';
import {
  cacheConversations,
  readCachedConversations,
} from '@/lib/offline-cache';
import type { CachedConversation, Conversation, FetchPageResult } from '@/types';

const PAGE_SIZE = 20;

async function fetchConversationPage(cursor?: string): Promise<FetchPageResult<Conversation>> {
  // Backend supports ?cursor= for keyset pagination; falls back to offset if absent.
  // listConversationsByCursor returns Result<…, ClawError> and never throws, so we
  // unwrap explicitly: throw on Err so usePagination's error state surfaces a real
  // failure instead of silently treating the Err object as page data (prior crash).
  const result = await api.listConversationsByCursor(cursor, PAGE_SIZE);
  if (!result.ok) {
    throw new Error(getClawErrorMessage(result.error));
  }
  return { items: result.value.data, nextCursor: result.value.nextCursor };
}

function HistorySkeleton(): React.ReactElement {
  return (
    <div
      aria-label="Loading history"
      role="status"
      style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}
    >
      {[0, 1, 2, 3, 4].map((i) => (
        <div
          key={i}
          style={{
            padding: '12px 16px',
            borderRadius: '12px',
            background: 'var(--color-surface)',
            display: 'flex',
            flexDirection: 'column',
            gap: '6px',
          }}
        >
          <Skeleton variant="text" width="70%" height={16} />
          <Skeleton variant="text" width="40%" height={12} />
        </div>
      ))}
    </div>
  );
}

function HistoryEmpty(): React.ReactElement {
  return (
    <div
      role="status"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '3rem 2rem',
        gap: '0.75rem',
        textAlign: 'center',
        color: 'var(--color-text-muted)',
      }}
    >
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>No history yet</p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>
        Your past conversations will appear here automatically.
      </p>
    </div>
  );
}

export default function HistoryPage(): React.ReactElement {
  const fetchPage = useCallback(
    (cursor?: string) => fetchConversationPage(cursor),
    [],
  );

  const { items, loadMore, hasMore, loading, error, reset } = usePagination<Conversation>(fetchPage);
  const { isOnline } = useNetworkStatus();
  const [cachedItems, setCachedItems] = useState<CachedConversation[]>([]);
  const [cacheStale, setCacheStale] = useState(false);

  // Load first page on mount.
  useEffect(() => { loadMore(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // When online and data loads, write to IndexedDB cache.
  useEffect(() => {
    if (!isOnline || items.length === 0) return;
    void cacheConversations(items, {});
  }, [isOnline, items]);

  // When offline, read IndexedDB cache.
  useEffect(() => {
    if (isOnline) {
      setCacheStale(false);
      return;
    }
    void readCachedConversations().then((cached) => {
      if (cached.length > 0) {
        setCachedItems(cached);
        setCacheStale(true);
      }
    });
  }, [isOnline]);

  // When coming back online, auto-refresh.
  useEffect(() => {
    if (isOnline && cacheStale) {
      setCacheStale(false);
      reset();
      loadMore();
    }
  }, [isOnline, cacheStale, reset, loadMore]);

  // Effective items: network data when online; cached data when offline.
  const effectiveItems: Array<Conversation | CachedConversation> =
    !isOnline && cachedItems.length > 0 ? cachedItems : items;

  return (
    <main className="mx-auto max-w-2xl w-full px-4 py-10 flex flex-col gap-6">
      <OfflineBanner isOnline={isOnline} />

      {/* Stale cache banner — shown when serving IndexedDB data offline */}
      {cacheStale && !isOnline && cachedItems.length > 0 && (
        <div
          role="status"
          style={{
            padding: '10px 14px',
            borderRadius: 8,
            background: 'rgba(234,179,8,0.1)',
            color: 'var(--color-warning, #eab308)',
            fontSize: 13,
          }}
        >
          Cached &mdash; showing {cachedItems.length} conversations. Some messages may be newer.
        </div>
      )}

      <header>
        <h1 className="text-2xl font-semibold" style={{ color: 'var(--color-text)' }}>
          History
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)' }}>
          All past conversations
        </p>
      </header>

      <AsyncScreen
        loading={loading && effectiveItems.length === 0}
        empty={!loading && effectiveItems.length === 0 && !error}
        error={error}
        offline={!isOnline && effectiveItems.length === 0}
        onRetry={() => { reset(); loadMore(); }}
        skeleton={<HistorySkeleton />}
        emptyContent={<HistoryEmpty />}
      >
        <ul className="flex flex-col gap-3" aria-label="Conversation history">
          {effectiveItems.map((conv) => (
            <li
              key={conv.id}
              className="rounded-xl px-4 py-3"
              style={{ background: 'var(--color-surface)' }}
            >
              <a
                href={`/chat/${conv.id}`}
                className="block text-sm font-medium"
                style={{ color: 'var(--color-text)' }}
              >
                {conv.title || 'Untitled conversation'}
              </a>
              <p className="text-xs mt-0.5" style={{ color: 'var(--color-text-muted)' }}>
                {new Date(conv.updatedAt).toLocaleDateString()} · {conv.messageCount} messages
              </p>
            </li>
          ))}
        </ul>

        {loading && items.length > 0 && (
          <p className="text-center text-sm py-4" style={{ color: 'var(--color-text-muted)' }}>
            Loading more&hellip;
          </p>
        )}

        {!loading && hasMore && (
          <button
            type="button"
            onClick={loadMore}
            className="mx-auto px-6 py-2 rounded-full text-sm font-medium"
            style={{ background: 'var(--color-primary)', color: 'var(--color-on-primary)' }}
          >
            Load more
          </button>
        )}

        {!loading && !hasMore && items.length > 0 && (
          <p className="text-center text-xs py-2" style={{ color: 'var(--color-text-muted)' }}>
            All conversations loaded
          </p>
        )}
      </AsyncScreen>
    </main>
  );
}
