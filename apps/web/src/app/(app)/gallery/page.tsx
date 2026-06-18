'use client';

/**
 * /gallery — Image gallery with cursor-paginated thumbnails.
 *
 * Purpose: Browse AI-generated or uploaded images with Load more pagination.
 *          AsyncScreen handles all 7 UI states; skeleton matches the image grid layout.
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

interface GalleryImage {
  id: string;
  url: string;
  prompt: string | null;
  width: number;
  height: number;
  createdAt: string;
}

const PAGE_SIZE = 20;

async function fetchGalleryPage(cursor?: string): Promise<FetchPageResult<GalleryImage>> {
  const url = cursor
    ? `/claw/gallery?cursor=${encodeURIComponent(cursor)}&pageSize=${PAGE_SIZE}`
    : `/claw/gallery?pageSize=${PAGE_SIZE}`;
  const page = await (api as unknown as {
    request: <T>(path: string) => Promise<{ data: T[]; nextCursor: string | null }>;
  }).request<GalleryImage>(url);
  return { items: page.data, nextCursor: page.nextCursor };
}

function GallerySkeleton(): React.ReactElement {
  return (
    <div
      aria-label="Loading gallery"
      role="status"
      className="grid gap-3"
      style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))' }}
    >
      {[0, 1, 2, 3, 4, 5].map((i) => (
        <Skeleton key={i} variant="rect" style={{ aspectRatio: '1 / 1', borderRadius: '12px' }} />
      ))}
    </div>
  );
}

function GalleryEmpty(): React.ReactElement {
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
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>No images yet</p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>
        Generate or share an image in a conversation and it will appear here.
      </p>
    </div>
  );
}

export default function GalleryPage(): React.ReactElement {
  const fetchFn = useCallback((cursor?: string) => fetchGalleryPage(cursor), []);
  const { items, loadMore, hasMore, loading, error, reset } = usePagination<GalleryImage>(fetchFn);
  const { isOnline } = useNetworkStatus();

  useEffect(() => { loadMore(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <main className="mx-auto max-w-3xl w-full px-4 py-10 flex flex-col gap-6">
      <OfflineBanner isOnline={isOnline} />

      <header>
        <h1 className="text-2xl font-semibold" style={{ color: 'var(--color-text)' }}>
          Gallery
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)' }}>
          Images generated or shared in your conversations
        </p>
      </header>

      <AsyncScreen
        loading={loading && items.length === 0}
        empty={!loading && items.length === 0 && !error}
        error={error}
        offline={!isOnline}
        onRetry={() => { reset(); loadMore(); }}
        skeleton={<GallerySkeleton />}
        emptyContent={<GalleryEmpty />}
      >
        <div
          className="grid gap-3"
          style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))' }}
          aria-label="Image gallery"
        >
          {items.map((img) => (
            <figure
              key={img.id}
              className="rounded-xl overflow-hidden m-0"
              style={{ background: 'var(--color-surface)' }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={img.url}
                alt={img.prompt ?? 'Gallery image'}
                className="w-full object-cover"
                style={{ aspectRatio: '1 / 1' }}
                loading="lazy"
              />
              {img.prompt && (
                <figcaption
                  className="text-xs px-2 py-1 line-clamp-2"
                  style={{ color: 'var(--color-text-muted)' }}
                >
                  {img.prompt}
                </figcaption>
              )}
            </figure>
          ))}
        </div>

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
            All images loaded
          </p>
        )}
      </AsyncScreen>
    </main>
  );
}
