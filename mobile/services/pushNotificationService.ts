/**
 * Purpose: FCM push notification service for ɳClaw mobile.
 *   Registers Expo + FCM push tokens with the nclaw backend, handles token refresh,
 *   and wires Android notification channels for notification grouping by topic_id.
 *   iOS permission request is NOT triggered here — it is triggered during onboarding
 *   via requestPushPermission() called from OnboardingScreen.
 *
 * Inputs:
 *   - Expo push token (obtained via getExpoPushTokenAsync)
 *   - FCM token (obtained via getDevicePushTokenAsync on Android)
 *   - Server base URL (EXPO_PUBLIC_NCLAW_API_URL)
 *   - Auth token (from @nself/auth-core authStrategy)
 *
 * Outputs:
 *   - Token registered at POST /api/devices/register on nclaw backend
 *   - Token refresh subscription via addPushTokenListener (no stale tokens)
 *   - Android notification channels per topic_id (grouping support)
 *   - Cleanup function to remove listener
 *
 * Constraints:
 *   - expo-notifications must be installed (peer dep — added to package.json by T06).
 *   - NEVER log raw FCM tokens.
 *   - requestPushPermission() returns early if permission already granted (idempotent).
 *   - registerDeviceToken() is idempotent — safe to call on every app launch.
 *   - On Android, setNotificationChannelAsync is idempotent (no-op if channel exists).
 *   - Token refresh re-registers immediately via addPushTokenListener.
 *
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-fcm
 * Cross-ref: T-P3-E4-W2-S3-T06 (push notifications surface), T14 (this ticket)
 */

import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import { authStrategy } from '../lib/auth';

// ─── Constants ────────────────────────────────────────────────────────────────

/** nclaw backend base URL (no trailing slash). */
const NCLAW_API_URL =
  (process.env.EXPO_PUBLIC_NCLAW_API_URL ?? process.env.EXPO_PUBLIC_NSELF_API_URL ?? 'http://localhost:3710').replace(/\/$/, '');

/** ɳClaw brand purple (notification icon tint / Android notification color). */
const NCLAW_BRAND_COLOR = '#6C3CE1';

/** Default Android notification channel ID (fallback if no topic). */
const DEFAULT_CHANNEL_ID = 'nclaw-default';

// ─── Types ────────────────────────────────────────────────────────────────────

/** Shape of the payload sent to /api/devices/register. */
interface DeviceRegisterPayload {
  /** Expo push token string (ExponentPushToken[…]). */
  expoPushToken: string;
  /** Raw FCM registration token (Android) or APNs device token (iOS). */
  platformToken: string;
  /** 'ios' | 'android' */
  platform: string;
}

// ─── Permission ───────────────────────────────────────────────────────────────

/**
 * Request push notification permission from the OS.
 * Idempotent — returns 'granted' immediately if already approved.
 * Called during OnboardingScreen 'notifications' step (never on cold launch).
 *
 * @returns 'granted' | 'denied' | 'undetermined'
 */
export async function requestPushPermission(): Promise<Notifications.PermissionStatus> {
  const { status: existing } = await Notifications.getPermissionsAsync();
  if (existing === 'granted') return existing;

  const { status } = await Notifications.requestPermissionsAsync({
    ios: {
      allowAlert: true,
      allowBadge: true,
      allowSound: true,
      allowDisplayInCarPlay: false,
      allowCriticalAlerts: false,
    },
  });
  return status;
}

// ─── Android channels ─────────────────────────────────────────────────────────

/**
 * Ensure the default Android notification channel exists.
 * Called once at app launch (idempotent — no-op if channel already exists).
 */
export async function ensureDefaultNotificationChannel(): Promise<void> {
  if (Platform.OS !== 'android') return;

  await Notifications.setNotificationChannelAsync(DEFAULT_CHANNEL_ID, {
    name: 'ɳClaw',
    description: 'ɳClaw general notifications',
    importance: Notifications.AndroidImportance.HIGH,
    vibrationPattern: [0, 250, 250, 250],
    lightColor: NCLAW_BRAND_COLOR,
    enableVibrate: true,
    showBadge: true,
  });
}

/**
 * Ensure a per-topic Android notification channel exists.
 * Grouped notifications from the same topic_id appear under one channel heading.
 * Idempotent — setNotificationChannelAsync is a no-op if the channel already exists.
 *
 * @param topicId  Canonical topic tag (e.g. 'code', 'planning', 'personal')
 * @param label    Human-readable channel name shown in OS settings
 */
export async function ensureTopicNotificationChannel(topicId: string, label: string): Promise<void> {
  if (Platform.OS !== 'android') return;

  const channelId = `nclaw-topic-${topicId}`;
  await Notifications.setNotificationChannelAsync(channelId, {
    name: `ɳClaw — ${label}`,
    description: `Notifications grouped by topic: ${label}`,
    importance: Notifications.AndroidImportance.DEFAULT,
    vibrationPattern: [0, 100],
    lightColor: NCLAW_BRAND_COLOR,
    enableVibrate: true,
    showBadge: true,
    groupId: channelId,
  });
}

// ─── Token registration ────────────────────────────────────────────────────────

/**
 * Register the device's push token with the nclaw backend.
 * Called on app launch (if permission granted) and whenever the token refreshes.
 * Silently returns on error — push is non-critical.
 *
 * @param expoPushToken  Expo push token string (ExponentPushToken[…])
 * @param platformToken  Raw FCM (Android) or APNs (iOS) device token
 */
async function registerDeviceToken(expoPushToken: string, platformToken: string): Promise<void> {
  try {
    const token = await authStrategy.getAccessToken();
    const payload: DeviceRegisterPayload = {
      expoPushToken,
      platformToken,
      platform: Platform.OS,
    };

    const response = await fetch(`${NCLAW_API_URL}/api/devices/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      // Non-critical — log at warn level only, never throw
      console.warn('[PushNotificationService] device register failed', response.status);
    }
  } catch {
    // Network error — non-critical; silently swallow
    console.warn('[PushNotificationService] device register network error');
  }
}

// ─── Initialisation ────────────────────────────────────────────────────────────

/** Opaque subscription handle returned by init — pass to cleanup(). */
export interface PushNotificationServiceHandle {
  remove: () => void;
}

/**
 * Initialise the FCM push notification service.
 *
 * 1. Check push permission — bail silently if not granted.
 * 2. Get Expo push token + native FCM/APNs token.
 * 3. POST both tokens to /api/devices/register.
 * 4. Subscribe to token refresh events — re-register on change.
 * 5. Ensure the default Android notification channel exists.
 *
 * @returns A handle with a remove() function. Call handle.remove() on unmount.
 */
export async function initPushNotificationService(): Promise<PushNotificationServiceHandle> {
  // No-op handle for bail-out cases
  const noopHandle: PushNotificationServiceHandle = { remove: () => {} };

  // Check permission — only proceed if granted
  const { status } = await Notifications.getPermissionsAsync();
  if (status !== 'granted') return noopHandle;

  // Ensure default channel on Android
  await ensureDefaultNotificationChannel();

  // Get Expo push token
  let expoPushToken: string;
  try {
    const tokenData = await Notifications.getExpoPushTokenAsync({
      projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID,
    });
    expoPushToken = tokenData.data;
  } catch {
    console.warn('[PushNotificationService] could not get Expo push token');
    return noopHandle;
  }

  // Get native platform token (FCM on Android, APNs on iOS)
  let platformToken: string;
  try {
    const deviceTokenData = await Notifications.getDevicePushTokenAsync();
    platformToken = deviceTokenData.data as string;
  } catch {
    // Fall back to expoPushToken — backend can still route via Expo
    platformToken = expoPushToken;
  }

  // Register with backend
  await registerDeviceToken(expoPushToken, platformToken);

  // Subscribe to token refresh — re-register immediately on change
  const subscription = Notifications.addPushTokenListener(async (newToken) => {
    const newExpoPushToken = typeof newToken.data === 'string' ? newToken.data : expoPushToken;
    await registerDeviceToken(newExpoPushToken, newExpoPushToken);
  });

  return {
    remove: () => subscription.remove(),
  };
}
