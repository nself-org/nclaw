/**
 * retry.ts — useRetry hook and retryable fetch wrapper
 *
 * Purpose: Wraps async functions with exponential-backoff retry logic for transient
 *          network errors. Non-retryable errors (auth, permission, validation) are
 *          rethrown immediately without consuming retry attempts.
 *
 * Inputs:
 *   fn          — async fn to wrap
 *   maxAttempts — default 3
 *   baseDelay   — ms before first retry, default 1000
 *   maxDelay    — ms cap on any single delay, default 30 000
 *   shouldRetry — predicate (ClawError) => boolean; defaults to retryable flag
 *
 * Outputs: Promise<T> — resolves on success, rejects after all attempts exhausted.
 *
 * Constraints:
 *   - Jittered exponential backoff: delay = min(maxDelay, baseDelay * 2^attempt) * (0.75..1.25)
 *   - Non-retryable ClawError types (auth, context_overflow, quota_exceeded, unknown) bail.
 *   - Retryable types (network, rate_limit, model_unavailable, tool_error) retry.
 *   - Never retries if AbortSignal is already aborted.
 *   - ClawError canonical type is imported from ./result to avoid duplication.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: edge-case resilience
 */

import { useCallback } from 'react';
import type { ClawError } from './result';

export type { ClawError };

/** Default predicate: retry based on ClawError.retryable flag or error type. */
function defaultShouldRetry(err: unknown): boolean {
  if (err && typeof err === 'object' && 'retryable' in err) {
    return Boolean((err as { retryable: boolean }).retryable);
  }
  // Raw HTTP status fallback for non-ClawError throws.
  if (err && typeof err === 'object' && 'status' in err) {
    const s = (err as { status: number }).status;
    if ([400, 401, 403, 404, 409, 422].includes(s)) return false;
    return s === 429 || s >= 500;
  }
  // No-status = network error = retryable.
  return true;
}

function jitteredDelay(attempt: number, baseDelay: number, maxDelay: number): number {
  const exponential = baseDelay * Math.pow(2, attempt);
  const capped = Math.min(maxDelay, exponential);
  // ±25% jitter
  const jitter = capped * (0.75 + Math.random() * 0.5);
  return Math.floor(jitter);
}

export interface RetryOptions {
  maxAttempts?: number;
  baseDelay?: number;
  maxDelay?: number;
  shouldRetry?: (err: unknown) => boolean;
  signal?: AbortSignal;
}

/**
 * withRetry — standalone async retry wrapper (not a hook; usable outside React).
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {},
): Promise<T> {
  const {
    maxAttempts = 3,
    baseDelay = 1_000,
    maxDelay = 30_000,
    shouldRetry = defaultShouldRetry,
    signal,
  } = options;

  let lastErr: unknown = new Error('Unknown error');

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (signal?.aborted) {
      throw Object.assign(new Error('Aborted'), { name: 'AbortError' });
    }

    try {
      return await fn();
    } catch (err) {
      lastErr = err;

      const isLastAttempt = attempt === maxAttempts - 1;
      if (isLastAttempt || !shouldRetry(lastErr)) {
        throw lastErr;
      }

      const delay = jitteredDelay(attempt, baseDelay, maxDelay);
      await new Promise<void>((resolve, reject) => {
        const t = setTimeout(resolve, delay);
        if (signal) {
          signal.addEventListener('abort', () => {
            clearTimeout(t);
            reject(Object.assign(new Error('Aborted'), { name: 'AbortError' }));
          }, { once: true });
        }
      });
    }
  }

  throw lastErr;
}

/**
 * useRetry — React hook that returns a stable `run` function wrapping withRetry.
 *
 * Usage:
 *   const { run } = useRetry({ maxAttempts: 3 });
 *   const result = await run(() => api.saveMemory(entity));
 */
export function useRetry(options: RetryOptions = {}): {
  run: <T>(fn: () => Promise<T>) => Promise<T>;
} {
  const run = useCallback(
    <T>(fn: () => Promise<T>) => withRetry(fn, options),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      options.maxAttempts,
      options.baseDelay,
      options.maxDelay,
      options.signal,
    ],
  );

  return { run };
}

export default useRetry;
