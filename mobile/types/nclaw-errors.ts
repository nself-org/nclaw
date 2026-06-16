/**
 * NclawError — typed discriminated union for all libnclaw Rust FFI errors.
 *
 * Purpose: Provide a typed TS error surface for every error variant emitted
 *   by libnclaw through the @nself/native-bridge JSI seam. Prevents raw
 *   `catch(() => null)` anti-patterns; every call site returns
 *   Result<T, NclawError> so the UI can map error type to the correct
 *   AsyncScreen state (error / permission-denied / rate-limited / offline).
 *
 * Inputs:  Error values from @nself/native-bridge NativeNclaw calls.
 * Outputs: Typed NclawError discriminated union consumed by UI hooks and screens.
 *
 * Constraints:
 *   - Must mirror Rust error variants in nclaw/core/src/error.rs (source of truth).
 *   - No runtime values — types only; no classes or instances.
 *   - All variants are readonly to prevent accidental mutation.
 *   - Exported Result<T, NclawError> shorthand for convenience.
 *
 * SPORT: REGISTRY-NATIVE-APPS.md — nclaw/mobile typed_errors=true
 * Cross-ref: T-P3-E5-W3-S4-T01 (robustness sprint)
 *            @nself/native-bridge nclaw-ffi.ts (JSI seam)
 */

// =============================================================================
// Error variants (mirror Rust nclaw/core/src/error.rs)
// =============================================================================

/**
 * MemoryError — failure in the Rust memory layer (insert, search, compact).
 * Maps to AsyncScreen state: 'error'
 */
export interface MemoryError {
  readonly kind: 'MemoryError';
  /** Human-readable message from Rust. */
  readonly message: string;
  /** Rust error code (e.g. "db_locked", "corruption", "quota_exceeded"). */
  readonly code: string;
}

/**
 * LLMError — failure in the libnclaw inference pipeline (model, tokenizer, context).
 * Maps to AsyncScreen state: 'error'
 */
export interface LLMError {
  readonly kind: 'LLMError';
  /** Human-readable message from Rust. */
  readonly message: string;
  /** Rust error code (e.g. "context_overflow", "model_not_loaded", "inference_failed"). */
  readonly code: string;
}

/**
 * FFIError — failure in the JSI bridge itself (serialization, native crash, timeout).
 * Maps to AsyncScreen state: 'error'
 */
export interface FFIError {
  readonly kind: 'FFIError';
  /** Human-readable message. */
  readonly message: string;
  /** Optional original JS error for Sentry breadcrumbs. */
  readonly cause?: unknown;
}

/**
 * NetworkError — device offline or nSelf backend unreachable.
 * Maps to AsyncScreen state: 'offline'
 */
export interface NetworkError {
  readonly kind: 'NetworkError';
  readonly message: string;
}

/**
 * AuthError — session expired or insufficient permissions.
 * Maps to AsyncScreen state: 'permission-denied'
 */
export interface AuthError {
  readonly kind: 'AuthError';
  readonly message: string;
}

/**
 * RateLimitError — request rate exceeded by the server or local governor.
 * Maps to AsyncScreen state: 'rate-limited'
 */
export interface RateLimitError {
  readonly kind: 'RateLimitError';
  readonly message: string;
  /** Milliseconds until the caller may retry. */
  readonly retryAfterMs: number;
}

// =============================================================================
// Union type
// =============================================================================

/**
 * NclawError — all possible error types from libnclaw FFI and network stack.
 *
 * UI layer mapping:
 *   MemoryError | LLMError | FFIError  → AsyncScreen status='error'
 *   NetworkError                        → AsyncScreen status='offline'
 *   AuthError                           → AsyncScreen status='permission-denied'
 *   RateLimitError                      → AsyncScreen status='rate-limited' + retryAfterMs
 */
export type NclawError =
  | MemoryError
  | LLMError
  | FFIError
  | NetworkError
  | AuthError
  | RateLimitError;

// =============================================================================
// Result shorthand
// =============================================================================

/** Result<T, NclawError> — typed outcome for every native-bridge call site. */
export type NclawResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: NclawError };

// =============================================================================
// Constructors
// =============================================================================

/** Wrap a success value in a NclawResult. */
export function nclawOk<T>(value: T): NclawResult<T> {
  return { ok: true, value };
}

/** Wrap an error in a NclawResult. */
export function nclawErr<T>(error: NclawError): NclawResult<T> {
  return { ok: false, error };
}

// =============================================================================
// Classifier — map unknown caught values to NclawError
// =============================================================================

/**
 * classifyNclawError — convert any thrown/caught value to a typed NclawError.
 *
 * Call this in every @nself/native-bridge .catch() block instead of raw rethrow
 * or silent swallow. Sentry breadcrumbs should include the original `cause`.
 */
export function classifyNclawError(caught: unknown): NclawError {
  if (caught instanceof Error) {
    const msg = caught.message.toLowerCase();
    if (msg.includes('network') || msg.includes('offline') || msg.includes('unreachable')) {
      return { kind: 'NetworkError', message: caught.message };
    }
    if (msg.includes('auth') || msg.includes('unauthorized') || msg.includes('permission')) {
      return { kind: 'AuthError', message: caught.message };
    }
    if (msg.includes('rate') || msg.includes('too many')) {
      return { kind: 'RateLimitError', message: caught.message, retryAfterMs: 30_000 };
    }
    if (msg.includes('memory') || msg.includes('db_locked') || msg.includes('quota')) {
      return { kind: 'MemoryError', message: caught.message, code: 'unknown' };
    }
    if (msg.includes('context_overflow') || msg.includes('model') || msg.includes('inference')) {
      return { kind: 'LLMError', message: caught.message, code: 'unknown' };
    }
    return { kind: 'FFIError', message: caught.message, cause: caught };
  }
  return {
    kind: 'FFIError',
    message: typeof caught === 'string' ? caught : 'Unknown FFI error',
    cause: caught,
  };
}

// =============================================================================
// AsyncScreen state mapper
// =============================================================================

import type { ScreenStatus } from '../components/AsyncScreen';

/**
 * nclawErrorToScreenStatus — map a NclawError to the correct AsyncScreen state.
 *
 * @example
 * const status = result.ok ? 'data' : nclawErrorToScreenStatus(result.error);
 * <AsyncScreen status={status} retryAfterMs={rateLimitMs} ... />
 */
export function nclawErrorToScreenStatus(error: NclawError): ScreenStatus {
  switch (error.kind) {
    case 'NetworkError':
      return 'offline';
    case 'AuthError':
      return 'permission-denied';
    case 'RateLimitError':
      return 'rate-limited';
    case 'MemoryError':
    case 'LLMError':
    case 'FFIError':
    default:
      return 'error';
  }
}
