# ɳClaw Mobile — Native Capabilities

> Updated: 2026-06-16 | Migrated from Flutter platform channels → Expo SDK plugins (T-P3-E4-W2-S3-T06)

## Overview

ɳClaw mobile uses Expo SDK plugins in place of the Flutter platform channels from the original nself_claw app. Each capability maps 1:1 to a prior Flutter plugin.

| Capability | Flutter (archived) | Expo / React Native |
|---|---|---|
| Push notifications | `firebase_messaging` + platform channels | `expo-notifications` |
| Biometric auth | `local_auth` | `expo-local-authentication` |
| Background fetch | `workmanager` | `expo-background-fetch` + `expo-task-manager` |
| Secure storage | `flutter_secure_storage` | `expo-secure-store` |

---

## Push Notifications (`expo-notifications`)

### Architecture

Push notification support spans two layers:

1. **Surface / permission layer** (T06) — basic `expo-notifications` setup, foreground display policy.
2. **FCM layer** (T14) — full FCM token registration with nclaw backend, notification grouping by `topic_id`, and tap-to-navigate routing.

**Permission flow:**
- iOS permission prompt fires during onboarding step 3 (`notifications`) via `requestPushPermission()` in `pushNotificationService.ts`.
- Never triggered on cold launch (OS best-practice: timed ask after onboarding context).
- Returns 'denied' gracefully — user can enable later in Settings; onboarding continues.

**Token registration:**
- On app launch (if permission granted): `getExpoPushTokenAsync()` → Expo push token.
- `getDevicePushTokenAsync()` → raw FCM registration token (Android) or APNs token (iOS).
- Both tokens POSTed to `POST /api/devices/register` on the nclaw backend with `Authorization: Bearer <jwt>`.
- Token refresh handled by `addPushTokenListener` — re-registers immediately on change (no stale tokens).

**Notification grouping:**
- Android: per-`topic_id` notification channels created at app launch (`ensureCanonicalTopicChannels()`).
  All 9 canonical auto-topic channels pre-created (code, infra, admin, personal, research, question, task, planning, general).
  New topics: `ensureTopicChannel(topicId, label)` called lazily on first notification.
  Channel ID format: `nclaw-topic-<topicId>`.
- iOS: `threadIdentifier` set to `nclaw-topic-<topicId>` via `configureNotificationHandler()` at module level.
  iOS groups notifications with the same `threadIdentifier` under one header in Notification Center.

**Tap-to-navigate:**
- Notification payload must include `{thread_id?, screen?, topic_id?}`.
- `screen` values: `'chat'` (default), `'memory'`, `'history'`, `'topics'`.
- Foreground: `addNotificationResponseReceivedListener` fires immediately.
- Background/killed app: `getLastNotificationResponseAsync()` checked on first mount.
- Navigation logic lives entirely in `hooks/usePushNavigation.ts` — never in handler bodies.

### Notification Payload Shape

```json
{
  "thread_id": "uuid-of-thread",
  "screen": "chat",
  "topic_id": "code"
}
```

`screen` defaults to `'chat'` if omitted. `thread_id` is optional (routes to screen root if absent).

### Source files

- `services/pushNotificationService.ts` — FCM token registration, permission request, token refresh
- `services/notificationGroupingService.ts` — Android channels per topic_id, iOS thread identifier, global handler
- `hooks/usePushNavigation.ts` — tap-to-navigate (foreground + cold-start / killed app)
- `app/+layout.tsx` — wires `configureNotificationHandler()` (module level) + `initPushNotificationService()` + `usePushNavigation()` + `ensureCanonicalTopicChannels()`
- `app/onboarding.tsx` — triggers `requestPushPermission()` at onboarding step 3

---

## Biometric Auth (`expo-local-authentication`)

### Behaviour

- Optional (user preference). Disabled by default.
- When enabled: app locks on background → foreground transition (AppState `'active'`).
- Gate rendered in `app/+layout.tsx`: opaque overlay while `!isAuthenticated`.
- Graceful fallback: if biometrics not enrolled, enabling the preference is blocked with a warning. No crash.
- Device passcode fallback is offered via `disableDeviceFallback: false`.

### Preference key

`nclaw_biometric_enabled` in `expo-secure-store` (string `'true'` / `'false'`).

### Source files

- `hooks/useBiometricAuth.ts` — hook (enrollment check, AppState listener, authenticate)
- `app/+layout.tsx` — renders auth gate overlay

---

## Background Fetch (`expo-background-fetch` + `expo-task-manager`)

### Task name

`nclaw-memory-compaction`

### What it does

Calls `NativeNclaw.triggerCompaction()` (JSI bridge, `packages/native-bridge`) to run SQLite WAL compaction while the app is backgrounded. Triggered by the OS on its own schedule (minimum 15-minute interval, typically longer in practice).

### Return values

| Outcome | Result |
|---|---|
| Compaction succeeded | `BackgroundFetchResult.NewData` |
| JSI module unavailable | `BackgroundFetchResult.NewData` (non-fatal — retry scheduled) |
| Compaction threw | `BackgroundFetchResult.Failed` |

### Registration

Called from `app/+layout.tsx` via `registerMemoryCompactionTask()`. Idempotent — skips if already registered.

### Verification (developer)

```ts
import * as TaskManager from 'expo-task-manager';
const registered = await TaskManager.isTaskRegisteredAsync('nclaw-memory-compaction');
console.log(registered); // true
```

### Source files

- `tasks/memoryCompaction.ts` — task definition + registration helpers
- `app/+layout.tsx` — calls `registerMemoryCompactionTask()` on startup

---

## EAS / Physical Device Notes

- Push token registration requires a physical device (or simulator with push capabilities) and valid APNs entitlement / FCM `google-services.json`.
- Biometric authentication requires a physical device or a simulator with Face ID / Fingerprint enrolled.
- Background fetch is not reliably triggered in Expo Go — use a development build.

See `mobile-development.md` for EAS build profiles.
