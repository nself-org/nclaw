/**
 * Tests for lib/retry.ts — withRetry exponential backoff.
 *
 * Coverage:
 *   - Succeeds on first attempt (no retry)
 *   - Retries on retryable error (network = no status)
 *   - Stops immediately on non-retryable error (401, 403, 400, 422)
 *   - Does not exceed maxAttempts
 *   - Custom shouldRetry predicate is respected
 *   - AbortSignal cancels retry loop before first attempt
 *   - Non-retryable HTTP statuses: 400, 403, 404, 422 (no retry)
 *   - Retryable HTTP statuses: 429, 500, 503 (retries)
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { withRetry } from '../retry';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function networkErr(): Error & { retryable: boolean } {
  return Object.assign(new Error('Network error'), { retryable: true });
}

function authErr(): Error & { status: number; retryable: boolean } {
  return Object.assign(new Error('Unauthorized'), { status: 401, retryable: false });
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

// ─── withRetry ────────────────────────────────────────────────────────────────

describe('withRetry', () => {
  it('resolves immediately on first success (no retries)', async () => {
    const fn = vi.fn().mockResolvedValue('ok');
    const result = await withRetry(fn, { maxAttempts: 3 });
    expect(result).toBe('ok');
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('retries on retryable error up to maxAttempts', async () => {
    const fn = vi.fn()
      .mockRejectedValueOnce(networkErr())
      .mockRejectedValueOnce(networkErr())
      .mockResolvedValue('recovered');

    const promise = withRetry(fn, { maxAttempts: 3, baseDelay: 100, maxDelay: 1000 });
    await vi.runAllTimersAsync();
    const result = await promise;

    expect(result).toBe('recovered');
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it('stops immediately on non-retryable error (401)', async () => {
    const err = authErr();
    const fn = vi.fn().mockRejectedValue(err);

    await expect(
      withRetry(fn, { maxAttempts: 3, baseDelay: 100 }),
    ).rejects.toBe(err);

    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('throws after exhausting all maxAttempts', async () => {
    const err = networkErr();
    const fn = vi.fn().mockRejectedValue(err);

    const promise = withRetry(fn, { maxAttempts: 3, baseDelay: 10, maxDelay: 100 });
    await vi.runAllTimersAsync();

    await expect(promise).rejects.toBe(err);
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it('respects custom shouldRetry predicate', async () => {
    const shouldRetry = (e: unknown) =>
      e instanceof Error && (e as Error & { code?: string }).code === 'RETRY_ME';

    const retryableErr = Object.assign(new Error('retry'), { code: 'RETRY_ME' });
    const stopErr = Object.assign(new Error('stop'), { code: 'OTHER' });

    const fn = vi.fn()
      .mockRejectedValueOnce(retryableErr)
      .mockRejectedValue(stopErr);

    const promise = withRetry(fn, { maxAttempts: 5, baseDelay: 10, shouldRetry });
    await vi.runAllTimersAsync();

    await expect(promise).rejects.toBe(stopErr);
    expect(fn).toHaveBeenCalledTimes(2); // one retry, stopped on second
  });

  it('aborts immediately when signal is pre-aborted', async () => {
    const controller = new AbortController();
    controller.abort();

    const fn = vi.fn().mockResolvedValue('never');
    await expect(
      withRetry(fn, { maxAttempts: 3, signal: controller.signal }),
    ).rejects.toMatchObject({ name: 'AbortError' });

    expect(fn).not.toHaveBeenCalled();
  });

  it.each([400, 403, 404, 422])(
    'non-retryable HTTP %i does not retry',
    async (status) => {
      const err = Object.assign(new Error(`HTTP ${status}`), { status });
      const fn = vi.fn().mockRejectedValue(err);

      await expect(withRetry(fn, { maxAttempts: 3, baseDelay: 10 })).rejects.toBe(err);
      expect(fn).toHaveBeenCalledTimes(1);
    },
  );

  it.each([429, 500, 503])(
    'retryable HTTP %i retries',
    async (status) => {
      const err = Object.assign(new Error(`HTTP ${status}`), { status });
      const fn = vi.fn()
        .mockRejectedValueOnce(err)
        .mockResolvedValue('ok');

      const promise = withRetry(fn, { maxAttempts: 3, baseDelay: 10, maxDelay: 100 });
      await vi.runAllTimersAsync();

      const result = await promise;
      expect(result).toBe('ok');
      expect(fn).toHaveBeenCalledTimes(2);
    },
  );
});
