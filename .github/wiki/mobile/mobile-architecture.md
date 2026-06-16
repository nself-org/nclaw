# ɳClaw Mobile Architecture — Robustness & Offline Design

> **Status:** E5 W3 S4 — 7-state contract + offline sync + typed errors complete.
> See also: `mobile-chat-architecture.md`, `ffi-bridge.md`, `local-db.md`.

---

## 7-State AsyncScreen Contract

Every data-fetching screen in `nclaw/mobile` wraps its content in `<AsyncScreen>`.
The component handles **9 total states** (7 required by the E5 robustness spec):

| State | UI | Trigger |
|---|---|---|
| `loading` | Spinner + "Loading" text | Initial async operation in-flight |
| `skeleton` | Animated placeholder rows | Long-running fetch where skeleton is preferred |
| `empty` | Icon + CTA copy | Fetch succeeded but returned no items |
| `data` | Children rendered | Fetch succeeded with data |
| `error` | Typed error card + Retry button | Any `NclawError` mapped to `'error'` state |
| `offline` | Offline banner + queue indicator | `NetworkError` → `useNetworkStatus` `isOnline=false` |
| `permission-denied` | Re-auth prompt + Sign in button | `AuthError` from expired session |
| `rate-limited` | Countdown timer + Retry (post-countdown) | `RateLimitError` with `retryAfterMs` |
| `success` | Success icon | One-shot operation completed |

### Usage example

```tsx
import { AsyncScreen } from '../components/AsyncScreen';
import { nclawErrorToScreenStatus } from '../types/nclaw-errors';

const { isOnline } = useNetworkStatus();
const status = result
  ? (result.ok ? 'data' : nclawErrorToScreenStatus(result.error))
  : isOnline ? 'loading' : 'offline';

<AsyncScreen
  status={status}
  error={result?.ok === false ? result.error.message : undefined}
  retryAfterMs={result?.ok === false && result.error.kind === 'RateLimitError'
    ? result.error.retryAfterMs : undefined}
  onRetry={refetch}
  onReAuth={navigateToLogin}
>
  <ChatList messages={messages} />
</AsyncScreen>
```

---

## Typed Error Union — NclawError

All libnclaw Rust FFI errors surface as a typed `NclawError` discriminated union
defined in `mobile/types/nclaw-errors.ts`. No raw `.catch(() => null)` is permitted.

| Variant | AsyncScreen state | When |
|---|---|---|
| `MemoryError` | `'error'` | DB lock, corruption, quota |
| `LLMError` | `'error'` | Context overflow, model failure |
| `FFIError` | `'error'` | JSI bridge crash, serialization failure |
| `NetworkError` | `'offline'` | Device offline, backend unreachable |
| `AuthError` | `'permission-denied'` | Expired session, insufficient scope |
| `RateLimitError` | `'rate-limited'` | Too many requests; includes `retryAfterMs` |

Every `@nself/native-bridge` call site wraps its result in `NclawResult<T>`:

```ts
import { nclawOk, nclawErr, classifyNclawError } from '../types/nclaw-errors';

try {
  const response = await NativeNclaw.chatSend(text);
  return nclawOk(response);
} catch (err) {
  const nclawError = classifyNclawError(err);
  Sentry.addBreadcrumb({ category: 'nclaw-ffi', data: { kind: nclawError.kind } });
  return nclawErr(nclawError);
}
```

---

## Offline Mutation Queue

The queue is backed by `@react-native-async-storage/async-storage` so mutations
survive process kills and app restarts (MMKV-equivalent durability via Expo's
bundled AsyncStorage).

### Storage key

```
@nclaw/offline-queue/mutations
```

Namespaced — never collides with other AsyncStorage usage.

### Drain trigger

1. `useOfflineMutation` registers a listener via `useNetworkStatus().onConnected`.
2. On every offline → online transition, `drain(executor)` fires automatically.
3. Items are processed in insertion order; failures remain and are retried on the
   next drain call.

### Maestro test scenario

```yaml
# nclaw/mobile/tests/maestro/offline-queue-drain.yaml
- launchApp
- tapOn: "Chat"
- runScript: "enableAirplaneMode.js"     # disconnects network
- tapOn: "Type a message..."
- inputText: "offline message"
- tapOn: "Send"
- assertVisible: "Message sending..."    # optimistic UI
- runScript: "disableAirplaneMode.js"    # reconnects
- waitForAnimationToEnd
- assertVisible: "offline message"       # message confirmed in chat
- assertNotVisible: "Syncing..."         # queue drained
```

---

## Network Status Hook

`useNetworkStatus` provides a singleton NetInfo subscription shared across all
mounted components. It fires a `ConnectedListener` on every offline → online
transition without requiring a component re-render from all consumers.

```ts
const { isOnline, onConnected } = useNetworkStatus();
useEffect(() => onConnected(() => drainOfflineQueue()), []);
```

Falls back to polling `fetch HEAD https://1.1.1.1` on AppState `active` events
when `@react-native-community/netinfo` is unavailable.

---

## Sentry Integration

Sentry RN SDK is initialised in `app/_layout.tsx` via `@nself/observability`.
Every `NclawError` adds a Sentry breadcrumb with `category: 'nclaw-ffi'` and
`data: { kind }` so error types are traceable in the Sentry dashboard.

Screen transitions are captured automatically via `Sentry.wrap` (applied at the
root layout level).
