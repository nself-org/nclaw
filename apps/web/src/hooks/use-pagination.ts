'use client';

import { useCallback, useReducer, useRef } from 'react';
import type { FetchPageResult } from '@/types';

/**
 * usePagination<T>
 *
 * Purpose: Generic cursor-based pagination hook. Fetches pages via caller-supplied
 *          fetchPage and appends results on each loadMore call. Uses a string cursor
 *          (not offset) to avoid duplicate/missing items on concurrent writes.
 *
 * Inputs:
 *   fetchPage — async fn(cursor?: string) => { items: T[]; nextCursor: string | null }
 *
 * Outputs:
 *   items      — accumulated list of T across all loaded pages
 *   loadMore   — trigger next page fetch (no-op if loading or !hasMore)
 *   hasMore    — true when the last page returned a non-null nextCursor
 *   loading    — true during an in-flight loadMore call
 *   error      — last fetch error, or null (for AsyncScreen 7-state wiring)
 *   reset      — wipe accumulated items and cursor (e.g. on filter change)
 *
 * Constraints:
 *   - Append-only: loadMore never re-fetches earlier pages.
 *   - Concurrent loadMore calls are silently dropped while one is in-flight.
 *   - Cursor is always a string; offset-based pagination is out of scope.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: edge-case resilience
 */

export type { FetchPageResult };

interface State<T> {
  items: T[];
  cursor: string | null;
  hasMore: boolean;
  loading: boolean;
  error: unknown;
}

type Action<T> =
  | { type: 'FETCH_START' }
  | { type: 'FETCH_SUCCESS'; items: T[]; nextCursor: string | null }
  | { type: 'FETCH_ERROR'; error: unknown }
  | { type: 'RESET' };

function reducer<T>(state: State<T>, action: Action<T>): State<T> {
  switch (action.type) {
    case 'FETCH_START':
      return { ...state, loading: true, error: null };
    case 'FETCH_SUCCESS':
      return {
        items: [...state.items, ...action.items],
        cursor: action.nextCursor,
        hasMore: action.nextCursor !== null,
        loading: false,
        error: null,
      };
    case 'FETCH_ERROR':
      return { ...state, loading: false, error: action.error };
    case 'RESET':
      return { items: [], cursor: null, hasMore: true, loading: false, error: null };
    default:
      return state;
  }
}

export function usePagination<T>(
  fetchPage: (cursor?: string) => Promise<FetchPageResult<T>>,
): {
  items: T[];
  loadMore: () => void;
  hasMore: boolean;
  loading: boolean;
  error: unknown;
  reset: () => void;
} {
  const [state, dispatch] = useReducer(reducer as (s: State<T>, a: Action<T>) => State<T>, {
    items: [],
    cursor: null,
    hasMore: true,
    loading: false,
    error: null,
  });

  // Stable ref so loadMore closure never captures stale state.
  const stateRef = useRef(state);
  stateRef.current = state;

  const loadMore = useCallback(() => {
    const { loading, hasMore, cursor } = stateRef.current;
    if (loading || !hasMore) return;

    dispatch({ type: 'FETCH_START' });
    fetchPage(cursor ?? undefined)
      .then((result) => {
        dispatch({
          type: 'FETCH_SUCCESS',
          items: result.items,
          nextCursor: result.nextCursor,
        });
      })
      .catch((err: unknown) => {
        dispatch({ type: 'FETCH_ERROR', error: err });
      });
  }, [fetchPage]);

  const reset = useCallback(() => {
    dispatch({ type: 'RESET' });
  }, []);

  return {
    items: state.items,
    loadMore,
    hasMore: state.hasMore,
    loading: state.loading,
    error: state.error,
    reset,
  };
}

export default usePagination;
