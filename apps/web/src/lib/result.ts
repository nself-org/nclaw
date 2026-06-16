/**
 * Result<T,E> — discriminated-union typed error pattern for claw-web.
 *
 * Purpose: Eliminate untyped throw/catch chains. Every fallible async operation
 *          returns Result<T, ClawError> so callers handle success and failure at
 *          the type boundary — no surprise runtime throws.
 *
 * Inputs:  T — success value type; E — error type (defaults to ClawError).
 * Outputs: Discriminated union Ok<T> | Err<E>; helpers ok(), err(), mapResult(),
 *          unwrapOr(); ClawError discriminated union + getClawErrorMessage().
 *
 * Constraints:
 *   - No runtime dependencies beyond this file.
 *   - Never re-throw inside a Result helper — that defeats the purpose.
 *   - All ClawError variants carry retryable + optional retryAfter so callers
 *     can show a countdown without knowing the variant.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */

// ─── Core Result type ─────────────────────────────────────────────────────────

/** Successful result wrapper. */
export type Ok<T> = { readonly ok: true; readonly value: T };

/** Error result wrapper. */
export type Err<E> = { readonly ok: false; readonly error: E };

/**
 * Result<T, E> — canonical return type for all fallible claw-web operations.
 *
 * Narrow with:
 *   if (result.ok) { result.value } else { result.error }
 */
export type Result<T, E = ClawError> = Ok<T> | Err<E>;

/** Construct a successful Result. */
export const ok = <T>(value: T): Ok<T> => ({ ok: true, value });

/** Construct a failure Result. */
export const err = <E>(error: E): Err<E> => ({ ok: false, error });

/**
 * mapResult — transform the value inside an Ok, leaving Err unchanged.
 *
 * @example
 *   const r: Result<string> = ok('hello');
 *   const mapped = mapResult(r, (s) => s.length); // Result<number>
 */
export function mapResult<T, U, E>(
  result: Result<T, E>,
  fn: (value: T) => U
): Result<U, E> {
  if (result.ok) return ok(fn(result.value));
  return result;
}

/**
 * unwrapOr — extract the value or return a fallback for the Err case.
 *
 * @example
 *   const val = unwrapOr(result, null); // T | null
 */
export function unwrapOr<T, E>(result: Result<T, E>, fallback: T): T {
  return result.ok ? result.value : fallback;
}

/**
 * fromPromise — wrap a promise so it never rejects; catches and maps to Err.
 *
 * @param promise   The promise to wrap.
 * @param mapError  Maps the thrown value to an E. Defaults to identity cast.
 */
export async function fromPromise<T, E = ClawError>(
  promise: Promise<T>,
  mapError: (e: unknown) => E
): Promise<Result<T, E>> {
  try {
    return ok(await promise);
  } catch (e) {
    return err(mapError(e));
  }
}

// ─── ClawError discriminated union ───────────────────────────────────────────

/**
 * ClawErrorType — every failure mode the claw-web API layer can surface.
 *
 * Variants:
 *   network           — fetch failed (DNS, timeout, CORS, offline)
 *   auth              — 401/403, token expired or missing
 *   rate_limit        — 429, too many requests; retryAfter carries seconds
 *   model_unavailable — backend model not loaded / ollama not running
 *   context_overflow  — message too long; context window exceeded
 *   quota_exceeded    — monthly token/usage quota hit
 *   tool_error        — plugin / tool execution failed
 *   unknown           — unclassified error; message carries raw text
 */
export type ClawErrorType =
  | 'network'
  | 'auth'
  | 'rate_limit'
  | 'model_unavailable'
  | 'context_overflow'
  | 'quota_exceeded'
  | 'tool_error'
  | 'unknown';

/** ClawError — all metadata needed by the UI to display and handle an error. */
export interface ClawError {
  /** Discriminating variant key. */
  readonly type: ClawErrorType;
  /** Developer-facing message (not shown raw to users — use getClawErrorMessage). */
  readonly message: string;
  /** True if retrying the same operation is likely to succeed. */
  readonly retryable: boolean;
  /** Seconds to wait before retrying (present only for rate_limit). */
  readonly retryAfter?: number;
  /** HTTP status code if the error originated from a fetch response. */
  readonly status?: number;
}

// ─── Error factory helpers ────────────────────────────────────────────────────

/** Build a network ClawError from a fetch exception. */
export function networkError(cause: unknown): ClawError {
  const message =
    cause instanceof Error ? cause.message : 'Network request failed';
  return { type: 'network', message, retryable: true };
}

/** Build a ClawError from an HTTP response status + body. */
export function httpError(
  status: number,
  body: { message?: string; code?: string; retryAfter?: number }
): ClawError {
  if (status === 401 || status === 403) {
    return { type: 'auth', message: body.message ?? 'Unauthorized', retryable: false, status };
  }
  if (status === 429) {
    return {
      type: 'rate_limit',
      message: body.message ?? 'Rate limited',
      retryable: true,
      retryAfter: body.retryAfter,
      status,
    };
  }
  if (status === 507 || body.code === 'CONTEXT_OVERFLOW') {
    return { type: 'context_overflow', message: body.message ?? 'Context overflow', retryable: false, status };
  }
  if (status === 503 || body.code === 'MODEL_UNAVAILABLE') {
    return { type: 'model_unavailable', message: body.message ?? 'Model unavailable', retryable: true, status };
  }
  if (body.code === 'QUOTA_EXCEEDED') {
    return { type: 'quota_exceeded', message: body.message ?? 'Quota exceeded', retryable: false, status };
  }
  if (body.code === 'TOOL_ERROR') {
    return { type: 'tool_error', message: body.message ?? 'Tool error', retryable: true, status };
  }
  return { type: 'unknown', message: body.message ?? `HTTP ${status}`, retryable: false, status };
}

// ─── User-facing error messages ───────────────────────────────────────────────

/**
 * getClawErrorMessage — maps each ClawError variant to a user-friendly sentence.
 *
 * Never shows stack traces or raw "undefined" to users.
 * Rate limit messages include the retry countdown when retryAfter is present.
 */
export function getClawErrorMessage(e: ClawError): string {
  switch (e.type) {
    case 'network':
      return "Can't reach the server. Check your connection and try again.";
    case 'auth':
      return 'Your session has expired. Please sign in again.';
    case 'rate_limit':
      return e.retryAfter != null
        ? `You're sending messages too fast. Try again in ${e.retryAfter}s.`
        : "You're sending messages too fast. Please slow down.";
    case 'model_unavailable':
      return 'The AI model is not available right now. Try again in a moment.';
    case 'context_overflow':
      return 'Your message is too long for the current context window. Try a shorter message or start a new conversation.';
    case 'quota_exceeded':
      return "You've reached your usage limit for this period. Upgrade your plan to continue.";
    case 'tool_error':
      return 'A tool or plugin failed to execute. Try again or report this issue.';
    case 'unknown':
      return 'Something went wrong. Please try again or report this issue.';
  }
}
