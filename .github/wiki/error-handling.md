# Error Handling — claw-web

This document describes the typed-error pattern in use across the `claw-web` Next.js app.

---

## Result\<T, E\> Pattern

Every fallible API call returns a discriminated union instead of throwing:

```ts
type Result<T, E = ClawError> = Ok<T> | Err<E>;
// { ok: true; value: T } | { ok: false; error: E }
```

### Usage

```ts
import { ok, err, type Result } from '@/lib/result';

// Consuming
const result = await api.listConversations();
if (!result.ok) {
  console.error(getClawErrorMessage(result.error));
  return;
}
const conversations = result.value; // typed Conversation[]
```

### Helpers

| Helper | Signature | Purpose |
|--------|-----------|---------|
| `ok(value)` | `<T>(value: T) => Ok<T>` | Wrap a success value |
| `err(error)` | `<E>(error: E) => Err<E>` | Wrap an error |
| `mapResult(r, fn)` | Transform value inside `Ok`, pass `Err` through |
| `unwrapOr(r, fallback)` | Extract value or return fallback |
| `fromPromise(p, mapError)` | Wrap a promise that may reject |

---

## ClawError — Typed API Error Variants

All API errors surface as a `ClawError` discriminated union:

```ts
interface ClawError {
  type: ClawErrorType;
  message: string;    // developer-facing; use getClawErrorMessage() for UI
  retryable: boolean;
  retryAfter?: number; // seconds (rate_limit only)
  status?: number;    // HTTP status if applicable
}
```

### Variants

| Type | retryable | When |
|------|-----------|------|
| `network` | Yes | DNS failure, timeout, CORS, offline |
| `auth` | No | 401 / 403, expired or missing token |
| `rate_limit` | Yes | 429 Too Many Requests |
| `model_unavailable` | Yes | 503, Ollama model not loaded |
| `context_overflow` | No | Message exceeds context window |
| `quota_exceeded` | No | Monthly token/usage limit hit |
| `tool_error` | Yes | Plugin or tool execution failed |
| `unknown` | No | Unclassified error |

### User-Facing Messages

Use `getClawErrorMessage(error: ClawError): string` to get a user-friendly sentence for any variant. Never expose `error.message` directly in the UI.

```ts
import { getClawErrorMessage } from '@/lib/result';

// In a toast, inline error, or error boundary:
const msg = getClawErrorMessage(clawError);
// "You're sending messages too fast. Try again in 30s."
```

---

## Error Boundaries

Every route in claw-web is wrapped with `ErrorBoundary` at two levels:

1. **Client-side `ErrorBoundary` component** (`src/components/ErrorBoundary.tsx`) — wraps `{children}` in `(app)/layout.tsx`; catches React render errors. Renders an `ErrorCard` with "Reload" and "Report" CTAs.

2. **Next.js `error.tsx`** files in `(app)/` and `(auth)/` — catch async / server-side errors that escape React render. Each renders `ErrorCard`.

No route can show a blank screen on crash.

### Usage

```tsx
import { ErrorBoundary } from '@/components/ErrorBoundary';

// Already applied globally in (app)/layout.tsx:
<ErrorBoundary>{children}</ErrorBoundary>

// For per-section boundaries (e.g. isolate a sidebar crash):
<ErrorBoundary fallback={<SidebarFallback />}>
  <HeavySidebar />
</ErrorBoundary>
```

---

## Hooks

All `useClaw*` hooks return `ClawError | null` in their `error` field — never a raw `Error`. This allows callers to use `getClawErrorMessage()` directly without any casting.

```ts
const { messages, error } = useMessages(conversationId);
if (error) {
  const userMsg = getClawErrorMessage(error);
}
```

---

## What ErrorBoundaries Do NOT Catch

- Async errors inside event handlers (use `Result<T, ClawError>` there)
- Errors in `useEffect` that don't bubble to render
- Server-side (RSC) errors beyond what `error.tsx` handles

Use the `Result` pattern for all async API calls — do not rely on boundaries for those.
