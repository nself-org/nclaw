/**
 * Purpose: Hook that handles tap-to-navigate for ɳClaw push notifications.
 *   When a user taps a push notification, the payload {thread_id, screen} is
 *   parsed and expo-router navigates to the correct screen.
 *   Also handles the background (killed app) case — checks getLastNotificationResponseAsync
 *   on first mount and navigates if a pending response exists.
 *
 * Inputs:
 *   - Expo notification response events (addNotificationResponseReceivedListener)
 *   - expo-router (useRouter) for navigation
 *
 * Outputs:
 *   - Navigation side-effect when a notification is tapped (foreground or background)
 *   - Returns { lastNotificationResponse } for callers that need to inspect it
 *
 * Constraints:
 *   - Navigation logic MUST live in this hook — never in a notification handler body.
 *   - Cold-start (killed app): getLastNotificationResponseAsync checked on mount.
 *   - Foreground: addNotificationResponseReceivedListener fires on tap.
 *   - Listener is cleaned up on unmount (useEffect return).
 *   - Thread screen route: '/(tabs)/chat' with thread_id param when screen='chat'.
 *   - Memory screen route: '/(tabs)/memory' with optional params.
 *   - Unknown screens fall back to '/(tabs)/chat'.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T14 (FCM + tap-to-navigate), T02 (screen navigation)
 */

import { useEffect, useRef } from 'react';
import { useRouter } from 'expo-router';
import * as Notifications from 'expo-notifications';

// ─── Types ────────────────────────────────────────────────────────────────────

/** Expected shape of the push notification data payload. */
interface NotificationPayload {
  /** Thread ID to navigate to (for chat/thread notifications). */
  thread_id?: string;
  /** Target screen to open. Defaults to 'chat'. */
  screen?: 'chat' | 'memory' | 'history' | 'topics';
  /** Optional topic_id for context. */
  topic_id?: string;
}

// ─── Navigation helper ────────────────────────────────────────────────────────

/**
 * Parse the notification payload and push to the correct expo-router route.
 *
 * @param data    Notification data payload (may be anything — defensive typing)
 * @param router  expo-router router instance
 */
function navigateFromPayload(
  data: Record<string, unknown> | undefined,
  router: ReturnType<typeof useRouter>,
): void {
  if (!data) {
    router.push('/(tabs)/chat');
    return;
  }

  const payload = data as NotificationPayload;
  const screen = payload.screen ?? 'chat';
  const threadId = payload.thread_id;

  switch (screen) {
    case 'chat':
      if (threadId) {
        // Navigate to the specific thread in the chat screen
        router.push({
          pathname: '/(tabs)/chat',
          params: { thread_id: threadId },
        });
      } else {
        router.push('/(tabs)/chat');
      }
      break;

    case 'memory':
      router.push('/(tabs)/memory');
      break;

    case 'history':
      if (threadId) {
        router.push({
          pathname: '/(tabs)/history',
          params: { thread_id: threadId },
        });
      } else {
        router.push('/(tabs)/history');
      }
      break;

    case 'topics':
      router.push('/(tabs)/topics');
      break;

    default:
      // Unknown screen — fall back to chat
      router.push('/(tabs)/chat');
  }
}

// ─── Hook ──────────────────────────────────────────────────────────────────────

/**
 * usePushNavigation — wire push notification tap-to-navigate.
 *
 * Mount this hook once in the root layout. It registers a listener for
 * notification responses (taps) and handles the cold-start (killed app) case.
 *
 * @example
 *   // In app/+layout.tsx
 *   usePushNavigation();
 */
export function usePushNavigation(): void {
  const router = useRouter();
  // Ref to avoid re-registering on re-renders
  const handledInitialRef = useRef(false);

  useEffect(() => {
    // ── Cold-start (killed app) ──────────────────────────────────────────────
    // On first mount, check if the app was launched by tapping a notification.
    // getLastNotificationResponseAsync returns the most recent tapped notification
    // that has not yet been consumed.
    if (!handledInitialRef.current) {
      handledInitialRef.current = true;

      Notifications.getLastNotificationResponseAsync()
        .then((response) => {
          if (response) {
            const data = response.notification.request.content.data as
              | Record<string, unknown>
              | undefined;
            navigateFromPayload(data, router);
          }
        })
        .catch(() => {
          // Non-critical — ignore errors in cold-start check
        });
    }

    // ── Foreground / background tap listener ─────────────────────────────────
    // Fires whenever the user taps a notification while the app is open or
    // was in the background (not killed).
    const subscription = Notifications.addNotificationResponseReceivedListener((response) => {
      const data = response.notification.request.content.data as
        | Record<string, unknown>
        | undefined;
      navigateFromPayload(data, router);
    });

    return () => {
      subscription.remove();
    };
  }, [router]);
}
