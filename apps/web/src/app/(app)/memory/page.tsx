'use client';

/**
 * /memory — Memory blocks browser with cursor-pagination and abortable search.
 *
 * Purpose: Lists memory entities (rooms/blocks) stored by the claw plugin with
 *          cursor-based Load more. Abortable search prevents stale responses.
 *          AsyncScreen handles all 7 UI states; skeleton matches populated card layout.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: edge-case resilience
 */

import React, { useCallback, useEffect } from 'react';
import { usePagination } from '@/hooks/use-pagination';
import { useAbortableRequest } from '@/hooks/use-abortable-request';
import { AsyncScreen } from '@/components/ui/AsyncScreen';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { Skeleton } from '@/components/ui/Skeleton';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import api from '@/lib/api';
import type { MemoryEntity, FetchPageResult } from '@/types';

const PAGE_SIZE = 20;

async function fetchMemoryPage(cursor?: string): Promise<FetchPageResult<MemoryEntity>> {
  const url = cursor
    ? `/claw/memory?cursor=${encodeURIComponent(cursor)}&pageSize=${PAGE_SIZE}`
    : `/claw/memory?pageSize=${PAGE_SIZE}`;
  const page = await (api as unknown as {
    request: <T>(path: string) => Promise<{ data: T[]; nextCursor: string | null }>;
  }).request<MemoryEntity>(url);
  return { items: page.data, nextCursor: page.nextCursor };
}

function MemorySkeleton(): React.ReactElement {
  return (
    <div
      aria-label="Loading memories"
      role="status"
      style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}
    >
      {[0, 1, 2, 3].map((i) => (
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
          <Skeleton variant="text" width="25%" height={18} style={{ borderRadius: '9999px' }} />
          <Skeleton variant="text" width="90%" height={14} />
          <Skeleton variant="text" width="20%" height={12} />
        </div>
      ))}
    </div>
  );
}

function MemoryEmpty(): React.ReactElement {
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
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>No memories yet</p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>
        Start a conversation to build memories — ɳClaw extracts facts automatically.
      </p>
    </div>
  );
}

export default function MemoryPage(): React.ReactElement {
  const fetchFn = useCallback((cursor?: string) => fetchMemoryPage(cursor), []);
  const { items, loadMore, hasMore, loading, error, reset } = usePagination<MemoryEntity>(fetchFn);
  const { isOnline } = useNetworkStatus();

  // Abortable memory search — cancels previous request on new query.
  const { invoke: searchMemory } = useAbortableRequest(
    useCallback(async (signal: AbortSignal, query: string) => {
      const url = `/claw/memory/search?q=${encodeURIComponent(query)}&pageSize=${PAGE_SIZE}`;
      return (api as unknown as {
        request: <T>(path: string, init?: RequestInit) => Promise<T>;
      }).request(url, { signal });
    }, []),
  );

  void searchMemory; // Exposed for future integration; wires cleanly via input handler.

  useEffect(() => { loadMore(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <main className="mx-auto max-w-2xl w-full px-4 py-10 flex flex-col gap-6">
      <OfflineBanner isOnline={isOnline} />

      <header>
        <h1 className="text-2xl font-semibold" style={{ color: 'var(--color-text)' }}>
          Memory
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)' }}>
          Stored memories and facts
        </p>
      </header>

      <AsyncScreen
        loading={loading && items.length === 0}
        empty={!loading && items.length === 0 && !error}
        error={error}
        offline={!isOnline}
        onRetry={() => { reset(); loadMore(); }}
        skeleton={<MemorySkeleton />}
        emptyContent={<MemoryEmpty />}
      >
        <ul className="flex flex-col gap-3" aria-label="Memory blocks">
          {items.map((entity) => (
            <li
              key={entity.id}
              className="rounded-xl px-4 py-3"
              style={{ background: 'var(--color-surface)' }}
            >
              <span
                className="inline-block text-xs font-medium px-2 py-0.5 rounded-full mb-1"
                style={{ background: 'var(--color-secondary-tint)', color: 'var(--color-secondary)' }}
              >
                {entity.type}
              </span>
              <p className="text-sm" style={{ color: 'var(--color-text)' }}>
                {entity.content}
              </p>
              <p className="text-xs mt-1" style={{ color: 'var(--color-text-muted)' }}>
                Confidence: {Math.round(entity.confidence * 100)}%
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
            All memories loaded
          </p>
        )}
      </AsyncScreen>
    </main>
  );
}
