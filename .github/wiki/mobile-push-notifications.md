# ɳClaw Mobile — Push Notifications (FCM + Grouping)

> Updated: 2026-06-16 | T-P3-E4-W2-S3-T14 — FCM full stack: token registration, grouping, tap-to-navigate.

---

## Overview

Push notification support in ɳClaw mobile spans two layers:

| Layer | Ticket | What it covers |
|---|---|---|
| Surface / permission | T06 | Basic `expo-notifications` setup, foreground display policy |
| FCM full stack | T14 (this doc) | FCM token registration + backend sync, notification grouping by `topic_id`, tap-to-navigate routing |

---

## Architecture

```
iOS / Android OS
       │
       ▼
 expo-notifications
       │
       ├── pushNotificationService.ts   ← FCM token registration + refresh
       ├── notificationGroupingService.ts ← Android channels + iOS thread IDs
       └── usePushNavigation.ts          ← tap-to-navigate (foreground + cold-start)
       │
       ▼
nclaw backend  POST /api/devices/register
```

---

## Permission Flow

- **iOS:** Permission prompt fires during onboarding step 3 (`notifications`) via `requestPushPermission()` in `pushNotificationService.ts`.
- **Never** triggered on cold launch (OS best-practice: timed ask with context).
- `'denied'` is non-fatal — user can enable later in Settings; onboarding continues.
- **Android:** Permission is granted by default (API < 33) or via system dialog on Android 13+ (handled by `expo-notifications` automatically).

```ts
// Called from OnboardingScreen (notifications step), not from _layout.tsx
const status = await requestPushPermission();
// 'denied' → continue onboarding, push silently disabled
```

---

## Token Registration

On each app launch (if permission granted):

1. `getExpoPushTokenAsync({ projectId })` → Expo push token (`ExponentPushToken[…]`)
2. `getDevicePushTokenAsync()` → raw FCM registration token (Android) or APNs device token (iOS)
3. Both tokens `POST`ed to `/api/devices/register` on the nclaw backend with `Authorization: Bearer <jwt>`

Token refresh is handled automatically:

```ts
Notifications.addPushTokenListener((newToken) => {
  // Re-registers immediately — no stale tokens in backend
  registerDeviceToken(expoPushToken, newToken.data);
});
```

**Backend endpoint:** `POST /api/devices/register`

```json
{
  "expoPushToken": "ExponentPushToken[...]",
  "platformToken": "<fcm-or-apns-token>",
  "platform": "ios" | "android"
}
```

---

## Notification Grouping

### Android — Notification Channels

Each `topic_id` gets its own Android notification channel so related notifications are grouped in the shade.

| Channel ID | Displayed name | When created |
|---|---|---|
| `nclaw-default` | ɳClaw | App launch (ensureDefaultNotificationChannel) |
| `nclaw-topic-code` | ɳClaw — Code | App launch (ensureCanonicalTopicChannels) |
| `nclaw-topic-planning` | ɳClaw — Planning | App launch |
| `nclaw-topic-<id>` | ɳClaw — `<label>` | Lazily on first notification for new topic |

All 9 canonical auto-topic channels are pre-created at app launch via `ensureCanonicalTopicChannels()`.
New custom topics are created lazily via `ensureTopicChannel(topicId, label)`.

Channel ID helper:

```ts
import { channelIdForTopic } from 'services/notificationGroupingService';
const channelId = channelIdForTopic('code'); // → 'nclaw-topic-code'
```

### iOS — Thread Identifier

iOS groups notifications under one header in Notification Center when they share the same `threadIdentifier`.

```ts
import { threadIdentifierForTopic } from 'services/notificationGroupingService';
const threadId = threadIdentifierForTopic('code'); // → 'nclaw-topic-code'
```

The global notification handler sets `threadIdentifier` automatically based on notification data at module load time via `configureNotificationHandler()`.

---

## Tap-to-Navigate

Tapping a push notification routes the user to the correct screen. Navigation logic lives entirely in `usePushNavigation` — **never** in handler bodies or notification listeners directly.

### Notification Payload Shape

```json
{
  "thread_id": "uuid",
  "screen": "chat" | "memory" | "history" | "topics",
  "topic_id": "code"
}
```

`screen` defaults to `'chat'` if absent.

### Routes

| `screen` value | Route | Notes |
|---|---|---|
| `chat` | `/(tabs)/chat` | Passes `thread_id` as param if present |
| `memory` | `/(tabs)/memory` | |
| `history` | `/(tabs)/history` | Passes `thread_id` as param if present |
| `topics` | `/(tabs)/topics` | |
| _(unknown)_ | `/(tabs)/chat` | Safe fallback |

### Cold-Start (Killed App)

When the app is launched by tapping a notification after being killed:

```ts
// usePushNavigation.ts — called in _layout.tsx
Notifications.getLastNotificationResponseAsync()
  .then((response) => {
    if (response) navigateFromPayload(response.notification.request.content.data, router);
  });
```

This is checked once on first mount via a `useRef` guard to avoid double-navigation.

---

## File Reference

| File | Purpose |
|---|---|
| `mobile/services/pushNotificationService.ts` | FCM token registration, permission, token refresh, Android default channel |
| `mobile/services/notificationGroupingService.ts` | Per-topic Android channels, iOS thread identifiers, global handler config |
| `mobile/hooks/usePushNavigation.ts` | Tap-to-navigate (foreground + cold-start) |
| `mobile/app/_layout.tsx` | Wires all three above at app startup |
| `mobile/app/onboarding.tsx` | Calls `requestPushPermission()` at notifications step |

---

## Testing

**Physical device required** for FCM token registration (simulator does not receive real push tokens).

### Manual QA

1. Send a test push to the device via the nclaw admin panel.
2. Tap the notification — verify it opens the correct screen.
3. Kill the app, re-send, tap — verify cold-start navigation works.
4. Verify the notification appears in the correct topic channel on Android (notification settings → app channels).
5. On iOS, send two notifications from the same topic — verify they group under one header.

### Automated Tests

```bash
cd nclaw/mobile
pnpm test services/pushNotificationService
pnpm test services/notificationGroupingService
pnpm test hooks/usePushNavigation
```

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `EXPO_PUBLIC_NCLAW_API_URL` | Yes | nclaw backend base URL (no trailing slash) |
| `EXPO_PUBLIC_EAS_PROJECT_ID` | Yes | EAS project ID for `getExpoPushTokenAsync` |

Fallback: `EXPO_PUBLIC_NSELF_API_URL` → `http://localhost:3710` (local dev only).

---

## Related Docs

- [native-capabilities.md](mobile/native-capabilities.md) — full Expo SDK capability map
- [mobile-chat-architecture.md](mobile/mobile-chat-architecture.md) — chat screen integration
- T-P3-E4-W2-S3-T06 — push notification surface coverage (permission + foreground display)
- T-P3-E4-W2-S3-T02 — screen navigation (thread routing target)
