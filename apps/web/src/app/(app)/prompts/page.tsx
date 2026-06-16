'use client';

/**
 * /prompts — Prompt library with cursor-paginated list.
 *
 * Purpose: Browse and Load more saved system/user prompt templates.
 *          AsyncScreen handles all 7 UI states; skeleton matches the prompt card layout.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: edge-case resilience
 */

import React, { useCallback, useEffect } from 'react';
import { usePagination } from '@/hooks/use-pagination';
import { AsyncScreen } from '@/components/ui/AsyncScreen';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { Skeleton } from '@/components/ui/Skeleton';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import api from '@/lib/api';
import type { FetchPageResult } from '@/types';

interface PromptTemplate {
  id: string;
  name: string;
  content: string;
  isSystem: boolean;
  createdAt: string;
}

const PAGE_SIZE = 20;

async function fetchPromptsPage(cursor?: string): Promise<FetchPageResult<PromptTemplate>> {
  const url = cursor
    ? `/claw/prompts?cursor=${encodeURIComponent(cursor)}&pageSize=${PAGE_SIZE}`
    : `/claw/prompts?pageSize=${PAGE_SIZE}`;
  const page = await (api as unknown as {
    request: <T>(path: string) => Promise<{ data: T[]; nextCursor: string | null }>;
  }).request(url);
  return { items: page.data, nextCursor: page.nextCursor };
}

function PromptsSkeleton(): React.ReactElement {
  return (
    <div
      aria-label="Loading prompts"
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
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <Skeleton variant="text" width="50%" height={16} />
            <Skeleton variant="text" width="14%" height={18} style={{ borderRadius: '4px' }} />
          </div>
          <Skeleton variant="text" width="95%" height={12} />
          <Skeleton variant="text" width="70%" height={12} />
        </div>
      ))}
    </div>
  );
}

function PromptsEmpty(): React.ReactElement {
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
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>No saved prompts yet</p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>
        Save a system prompt in settings or during a chat to see it here.
      </p>
    </div>
  );
}

export default function PromptsPage(): React.ReactElement {
  const fetchFn = useCallback((cursor?: string) => fetchPromptsPage(cursor), []);
  const { items, loadMore, hasMore, loading, error, reset } = usePagination<PromptTemplate>(fetchFn);
  const { isOnline } = useNetworkStatus();

  useEffect(() => { loadMore(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <main className="mx-auto max-w-2xl w-full px-4 py-10 flex flex-col gap-6">
      <OfflineBanner isOnline={isOnline} />

      <header>
        <h1 className="text-2xl font-semibold" style={{ color: 'var(--color-text)' }}>
          Prompt Library
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)' }}>
          Saved system and user prompt templates
        </p>
      </header>

      <AsyncScreen
        loading={loading && items.length === 0}
        empty={!loading && items.length === 0 && !error}
        error={error}
        offline={!isOnline}
        onRetry={() => { reset(); loadMore(); }}
        skeleton={<PromptsSkeleton />}
        emptyContent={<PromptsEmpty />}
      >
        <ul className="flex flex-col gap-3" aria-label="Prompt templates">
          {items.map((prompt) => (
            <li
              key={prompt.id}
              className="rounded-xl px-4 py-3"
              style={{ background: 'var(--color-surface)' }}
            >
              <div className="flex items-center gap-2 mb-1">
                <span className="text-sm font-medium" style={{ color: 'var(--color-text)' }}>
                  {prompt.name}
                </span>
                {prompt.isSystem && (
                  <span
                    className="text-xs px-1.5 py-0.5 rounded"
                    style={{ background: 'var(--color-primary-tint)', color: 'var(--color-primary)' }}
                  >
                    system
                  </span>
                )}
              </div>
              <p
                className="text-xs line-clamp-2"
                style={{ color: 'var(--color-text-muted)' }}
              >
                {prompt.content}
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
            All prompts loaded
          </p>
        )}
      </AsyncScreen>
    </main>
  );
}
