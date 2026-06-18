/**
 * Tests for lib/result.ts — Result<T,E> helpers and ClawError message map.
 *
 * Coverage:
 *   - All 7 ClawError variants → getClawErrorMessage returns non-generic string
 *   - rate_limit with retryAfter interpolation
 *   - ok() / err() constructors
 *   - mapResult() / unwrapOr() helpers
 *   - httpError() factory maps status codes correctly
 *   - networkError() factory maps thrown errors
 */

import { describe, it, expect } from 'vitest';
import {
  ok,
  err,
  mapResult,
  unwrapOr,
  fromPromise,
  getClawErrorMessage,
  httpError,
  networkError,
  type ClawError,
  type Result,
} from '../result';

// ─── ok / err constructors ────────────────────────────────────────────────────

describe('ok()', () => {
  it('sets ok:true and value', () => {
    const r = ok(42);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value).toBe(42);
  });
});

describe('err()', () => {
  it('sets ok:false and error', () => {
    const clawErr: ClawError = {
      type: 'unknown',
      message: 'test',
      retryable: false,
    };
    const r = err(clawErr);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toBe(clawErr);
  });
});

// ─── mapResult ────────────────────────────────────────────────────────────────

describe('mapResult()', () => {
  it('transforms the value of an Ok', () => {
    const r: Result<string> = ok('hello');
    const mapped = mapResult(r, (s) => s.length);
    expect(mapped.ok).toBe(true);
    if (mapped.ok) expect(mapped.value).toBe(5);
  });

  it('passes Err through unchanged', () => {
    const clawErr: ClawError = { type: 'auth', message: 'auth', retryable: false };
    const r: Result<string> = err(clawErr);
    const mapped = mapResult(r, (s: string) => s.length);
    expect(mapped.ok).toBe(false);
    if (!mapped.ok) expect(mapped.error).toBe(clawErr);
  });
});

// ─── unwrapOr ─────────────────────────────────────────────────────────────────

describe('unwrapOr()', () => {
  it('returns value for Ok', () => {
    expect(unwrapOr(ok(10), 0)).toBe(10);
  });

  it('returns fallback for Err', () => {
    const clawErr: ClawError = { type: 'network', message: 'down', retryable: true };
    expect(unwrapOr(err(clawErr), 0)).toBe(0);
  });
});

// ─── fromPromise ──────────────────────────────────────────────────────────────

describe('fromPromise()', () => {
  it('wraps a resolved promise in Ok', async () => {
    const r = await fromPromise(Promise.resolve(99), (e) => networkError(e));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value).toBe(99);
  });

  it('wraps a rejected promise in Err', async () => {
    const r = await fromPromise(
      Promise.reject(new Error('fail')),
      (e) => networkError(e)
    );
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.type).toBe('network');
      expect(r.error.message).toContain('fail');
    }
  });
});

// ─── httpError factory ────────────────────────────────────────────────────────

describe('httpError()', () => {
  it('maps 401 → auth variant', () => {
    const e = httpError(401, { message: 'Unauthorized' });
    expect(e.type).toBe('auth');
    expect(e.retryable).toBe(false);
  });

  it('maps 403 → auth variant', () => {
    const e = httpError(403, { message: 'Forbidden' });
    expect(e.type).toBe('auth');
  });

  it('maps 429 → rate_limit with retryAfter', () => {
    const e = httpError(429, { message: 'Too fast', retryAfter: 30 });
    expect(e.type).toBe('rate_limit');
    expect(e.retryAfter).toBe(30);
    expect(e.retryable).toBe(true);
  });

  it('maps CONTEXT_OVERFLOW code → context_overflow', () => {
    const e = httpError(400, { code: 'CONTEXT_OVERFLOW' });
    expect(e.type).toBe('context_overflow');
    expect(e.retryable).toBe(false);
  });

  it('maps 503 → model_unavailable', () => {
    const e = httpError(503, { message: 'Model not loaded' });
    expect(e.type).toBe('model_unavailable');
    expect(e.retryable).toBe(true);
  });

  it('maps QUOTA_EXCEEDED code → quota_exceeded', () => {
    const e = httpError(402, { code: 'QUOTA_EXCEEDED' });
    expect(e.type).toBe('quota_exceeded');
  });

  it('maps TOOL_ERROR code → tool_error', () => {
    const e = httpError(500, { code: 'TOOL_ERROR' });
    expect(e.type).toBe('tool_error');
  });

  it('maps unknown status → unknown', () => {
    const e = httpError(418, { message: "I'm a teapot" });
    expect(e.type).toBe('unknown');
  });
});

// ─── networkError factory ─────────────────────────────────────────────────────

describe('networkError()', () => {
  it('extracts message from Error', () => {
    const e = networkError(new Error('DNS lookup failed'));
    expect(e.type).toBe('network');
    expect(e.message).toBe('DNS lookup failed');
    expect(e.retryable).toBe(true);
  });

  it('handles non-Error thrown values', () => {
    const e = networkError('some string error');
    expect(e.type).toBe('network');
    expect(e.message).toBe('Network request failed');
  });
});

// ─── getClawErrorMessage — all 8 variants ─────────────────────────────────────

describe('getClawErrorMessage()', () => {
  const base = (type: ClawError['type'], overrides?: Partial<ClawError>): ClawError => ({
    type,
    message: 'raw',
    retryable: false,
    ...overrides,
  });

  it('network → mentions connection', () => {
    const msg = getClawErrorMessage(base('network'));
    expect(msg).not.toContain('undefined');
    expect(msg.length).toBeGreaterThan(10);
    expect(msg.toLowerCase()).toContain('connection');
  });

  it('auth → mentions sign in', () => {
    const msg = getClawErrorMessage(base('auth'));
    expect(msg.toLowerCase()).toMatch(/sign in|session/);
  });

  it('rate_limit without retryAfter — does not show NaN', () => {
    const msg = getClawErrorMessage(base('rate_limit'));
    expect(msg).not.toContain('NaN');
    expect(msg).not.toContain('undefined');
  });

  it('rate_limit with retryAfter — shows countdown', () => {
    const msg = getClawErrorMessage(base('rate_limit', { retryAfter: 15, retryable: true }));
    expect(msg).toContain('15s');
  });

  it('model_unavailable → mentions model/not available', () => {
    const msg = getClawErrorMessage(base('model_unavailable'));
    expect(msg.toLowerCase()).toMatch(/model|not available/);
  });

  it('context_overflow → mentions context/message too long', () => {
    const msg = getClawErrorMessage(base('context_overflow'));
    expect(msg.toLowerCase()).toMatch(/long|context/);
  });

  it('quota_exceeded → mentions limit/quota', () => {
    const msg = getClawErrorMessage(base('quota_exceeded'));
    expect(msg.toLowerCase()).toMatch(/limit|quota/);
  });

  it('tool_error → mentions tool/plugin', () => {
    const msg = getClawErrorMessage(base('tool_error'));
    expect(msg.toLowerCase()).toMatch(/tool|plugin/);
  });

  it('unknown → generic non-empty message', () => {
    const msg = getClawErrorMessage(base('unknown'));
    expect(msg).not.toContain('undefined');
    expect(msg.length).toBeGreaterThan(10);
  });

  // Verify no variant returns "undefined" or empty string
  const allVariants: ClawError['type'][] = [
    'network', 'auth', 'rate_limit', 'model_unavailable',
    'context_overflow', 'quota_exceeded', 'tool_error', 'unknown',
  ];

  it.each(allVariants)('variant %s → never returns generic/empty', (type) => {
    const msg = getClawErrorMessage(base(type));
    expect(msg).not.toBe('');
    expect(msg).not.toContain('undefined');
    expect(typeof msg).toBe('string');
  });
});
