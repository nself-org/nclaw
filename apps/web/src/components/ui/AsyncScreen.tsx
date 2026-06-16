'use client';

/**
 * AsyncScreen — 7-state data surface wrapper for all claw-web pages.
 *
 * Purpose: Single component that handles all 7 UI states any data-fetching
 *          page can be in. Mirrors the @nself/ui AsyncScreen contract so
 *          claw-web pages can be updated without pulling in the full package.
 *          State priority: loading > offline > error > rateLimited > permissionDenied > empty > populated.
 *
 * Inputs:
 *   - loading: boolean — TanStack Query fetching flag
 *   - empty: boolean — data length === 0 after successful fetch
 *   - error: unknown — any error thrown by the query
 *   - offline: boolean — from useNetworkStatus().isOnline === false
 *   - permissionDenied: boolean — 401/403 status code detected
 *   - rateLimited: boolean — 429 status code detected
 *   - retryAfter: number | undefined — seconds from Retry-After header (429 path)
 *   - onRetry: () => void — refetch callback
 *   - skeleton: ReactNode — layout-matching skeleton (REQUIRED — do not leave as default spinner)
 *   - emptyContent: ReactNode — context-appropriate empty-state CTA
 *   - children: ReactNode — populated state content
 *
 * Outputs: Appropriate state UI or children.
 * Constraints:
 *   - All pages MUST pass a custom skeleton and emptyContent (not the defaults).
 *   - Do not put data-fetching logic here — purely presentational.
 *
 * SOT: T-P3-E5-W1-S1-T01
 */

import React, { useEffect, useState } from 'react';
import { AlertCircle, Lock, WifiOff, Clock, RefreshCw } from 'lucide-react';
import { Skeleton } from '@/components/ui/Skeleton';
import { Button } from '@/components/ui/Button';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function isHttpError(e: unknown, status: number): boolean {
  return (
    typeof e === 'object' &&
    e !== null &&
    'status' in e &&
    (e as { status: unknown }).status === status
  );
}

// ─── Default slot UIs ────────────────────────────────────────────────────────

function DefaultSkeleton(): React.ReactElement {
  return (
    <div
      role="status"
      aria-label="Loading"
      style={{ display: 'flex', flexDirection: 'column', gap: '12px', padding: '24px' }}
    >
      <Skeleton variant="rect" height={40} />
      <Skeleton variant="rect" height={40} />
      <Skeleton variant="rect" height={40} />
    </div>
  );
}

function OfflineContent(): React.ReactElement {
  return (
    <div
      role="status"
      aria-live="polite"
      data-testid="async-screen-offline"
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
      <WifiOff size={40} aria-hidden="true" />
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>You&apos;re offline</p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>Check your connection and try again.</p>
    </div>
  );
}

interface ErrorContentProps {
  error: unknown;
  onRetry?: () => void;
}

function ErrorContent({ error, onRetry }: ErrorContentProps): React.ReactElement {
  const message =
    error instanceof Error
      ? error.message
      : typeof error === 'string'
      ? error
      : 'Something went wrong. Please try again.';

  return (
    <div
      role="alert"
      data-testid="async-screen-error"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '3rem 2rem',
        gap: '1rem',
        textAlign: 'center',
      }}
    >
      <AlertCircle size={40} aria-hidden="true" style={{ color: 'var(--color-error, #dc2626)' }} />
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>{message}</p>
      {onRetry !== undefined && (
        <Button variant="secondary" size="sm" onClick={onRetry} leftIcon={<RefreshCw size={14} />}>
          Retry
        </Button>
      )}
    </div>
  );
}

interface RateLimitedContentProps {
  retryAfter?: number;
  onRetry?: () => void;
}

function RateLimitedContent({ retryAfter, onRetry }: RateLimitedContentProps): React.ReactElement {
  const [countdown, setCountdown] = useState<number>(retryAfter ?? 0);

  useEffect(() => {
    if (!retryAfter || retryAfter <= 0) return;
    setCountdown(retryAfter);
    const interval = setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          clearInterval(interval);
          onRetry?.();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [retryAfter, onRetry]);

  return (
    <div
      role="status"
      data-testid="async-screen-rate-limited"
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
      <Clock size={40} aria-hidden="true" />
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>Rate limit reached</p>
      {countdown > 0 ? (
        <p style={{ margin: 0, fontSize: '0.875rem' }}>
          Retrying in <strong data-testid="rate-limit-countdown">{countdown}</strong>s&hellip;
        </p>
      ) : (
        <p style={{ margin: 0, fontSize: '0.875rem' }}>Please wait before trying again.</p>
      )}
      {countdown === 0 && onRetry !== undefined && (
        <Button variant="secondary" size="sm" onClick={onRetry}>
          Retry now
        </Button>
      )}
    </div>
  );
}

function PermissionDeniedContent(): React.ReactElement {
  return (
    <div
      role="status"
      data-testid="async-screen-permission-denied"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '3rem 2rem',
        gap: '0.75rem',
        textAlign: 'center',
      }}
    >
      <Lock size={40} aria-hidden="true" style={{ color: 'var(--color-text-muted)' }} />
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>Access restricted</p>
      <p style={{ margin: 0, fontSize: '0.875rem', color: 'var(--color-text-muted)' }}>
        You don&apos;t have permission to view this page.
      </p>
      <Button
        variant="primary"
        size="sm"
        onClick={() => {
          window.location.href = '/auth/signin';
        }}
      >
        Sign in again
      </Button>
    </div>
  );
}

// ─── AsyncScreen ─────────────────────────────────────────────────────────────

export interface AsyncScreenProps {
  /** TanStack Query fetching flag */
  loading: boolean;
  /** True when the data set is empty (after a successful fetch) */
  empty: boolean;
  /** Any error thrown by the query — null/undefined = no error */
  error?: unknown;
  /** Network offline flag — from useNetworkStatus().isOnline === false */
  offline?: boolean;
  /** 401/403 detected in the error */
  permissionDenied?: boolean;
  /** 429 detected in the error */
  rateLimited?: boolean;
  /** Seconds from Retry-After header (429 path) */
  retryAfter?: number;
  /** Refetch / refresh callback */
  onRetry?: () => void;
  /** Layout-matching skeleton — REQUIRED on every page */
  skeleton?: React.ReactNode;
  /** Context-appropriate empty-state CTA — REQUIRED on every page */
  emptyContent?: React.ReactNode;
  /** Populated state content */
  children: React.ReactNode;
}

export function AsyncScreen({
  loading,
  empty,
  error,
  offline = false,
  permissionDenied = false,
  rateLimited = false,
  retryAfter,
  onRetry,
  skeleton,
  emptyContent,
  children,
}: AsyncScreenProps): React.ReactElement {
  // Derive permission-denied and rate-limited from error status codes if not
  // explicitly provided, so callers can pass raw errors without pre-classifying.
  const isPermDenied =
    permissionDenied ||
    isHttpError(error, 401) ||
    isHttpError(error, 403);

  const isRateLimited =
    rateLimited ||
    isHttpError(error, 429);

  // 1. Loading
  if (loading) {
    return (
      <div data-testid="async-screen-loading">
        {skeleton ?? <DefaultSkeleton />}
      </div>
    );
  }

  // 2. Offline
  if (offline) {
    return <OfflineContent />;
  }

  // 3. Error (excluding 401/403/429 which have dedicated states)
  if (
    error !== undefined &&
    error !== null &&
    !isPermDenied &&
    !isRateLimited
  ) {
    return <ErrorContent error={error} onRetry={onRetry} />;
  }

  // 4. Rate limited
  if (isRateLimited) {
    return <RateLimitedContent retryAfter={retryAfter} onRetry={onRetry} />;
  }

  // 5. Permission denied
  if (isPermDenied) {
    return <PermissionDeniedContent />;
  }

  // 6. Empty
  if (empty) {
    return (
      <div data-testid="async-screen-empty">
        {emptyContent ?? (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '3rem 2rem',
              color: 'var(--color-text-muted)',
              fontSize: '0.875rem',
            }}
          >
            Nothing here yet.
          </div>
        )}
      </div>
    );
  }

  // 7. Populated
  return <div data-testid="async-screen-populated">{children}</div>;
}
