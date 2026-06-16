/**
 * Purpose: Manage push notification registration, permission, and deep-link routing for ɳClaw mobile.
 * Inputs: None (reads notification pref from expo-secure-store on mount).
 * Outputs: { registered, token, requestPermission, updatePref, prefs }.
 * Constraints: Requires physical device or capable simulator for FCM/APNs token. Expo SDK 51+.
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-notifications
 */
import { useEffect, useRef, useState, useCallback } from 'react';
import * as Notifications from 'expo-notifications';
import * as SecureStore from 'expo-secure-store';
import { router } from 'expo-router';
import { Platform } from 'react-native';

// ─── Types ────────────────────────────────────────────────────────────────────

export type NotificationType = 'insight_alert' | 'memory_summary' | 'topic_suggestion';

export interface NotificationPrefs {
  insight_alert: boolean;
  memory_summary: boolean;
  topic_suggestion: boolean;
}

export interface UseNotificationsReturn {
  /** Whether device token has been registered */
  registered: boolean;
  /** FCM/APNs device token (null until registered) */
  token: string | null;
  /** Request push permission and register token */
  requestPermission: () => Promise<boolean>;
  /** Update per-type notification preference */
  updatePref: (type: NotificationType, enabled: boolean) => Promise<void>;
  /** Current per-type preferences */
  prefs: NotificationPrefs;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const PREFS_STORE_KEY = 'nclaw_notification_prefs';
const TOKEN_STORE_KEY = 'nclaw_push_token';

const DEFAULT_PREFS: NotificationPrefs = {
  insight_alert: true,
  memory_summary: true,
  topic_suggestion: false,
};

// Map notification data.type → Expo Router route
const NOTIFICATION_ROUTE_MAP: Record<string, string> = {
  insight_alert: '/(tabs)/insights',
  memory_summary: '/(tabs)/memory',
  topic_suggestion: '/(tabs)/chat',
};

// ─── Notification handler (foreground display policy) ─────────────────────────

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function loadPrefs(): Promise<NotificationPrefs> {
  try {
    const stored = await SecureStore.getItemAsync(PREFS_STORE_KEY);
    if (stored) {
      return { ...DEFAULT_PREFS, ...JSON.parse(stored) };
    }
  } catch {
    // Return defaults on parse failure
  }
  return { ...DEFAULT_PREFS };
}

async function savePrefs(prefs: NotificationPrefs): Promise<void> {
  await SecureStore.setItemAsync(PREFS_STORE_KEY, JSON.stringify(prefs));
}

function resolveRouteFromNotification(
  notification: Notifications.Notification,
): string | null {
  const data = notification.request.content.data as Record<string, unknown>;
  const type = data?.type as string | undefined;
  const route = data?.route as string | undefined;

  // Explicit route wins; fall back to type map
  if (route && typeof route === 'string') return route;
  if (type && NOTIFICATION_ROUTE_MAP[type]) return NOTIFICATION_ROUTE_MAP[type];
  return null;
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

export function useNotifications(): UseNotificationsReturn {
  const [registered, setRegistered] = useState(false);
  const [token, setToken] = useState<string | null>(null);
  const [prefs, setPrefs] = useState<NotificationPrefs>(DEFAULT_PREFS);

  const responseListenerRef = useRef<Notifications.Subscription | null>(null);

  // Load persisted prefs and token on mount
  useEffect(() => {
    (async () => {
      const [storedPrefs, storedToken] = await Promise.all([
        loadPrefs(),
        SecureStore.getItemAsync(TOKEN_STORE_KEY).catch(() => null),
      ]);
      setPrefs(storedPrefs);
      if (storedToken) {
        setToken(storedToken);
        setRegistered(true);
      }
    })();

    // Deep-link listener: notification tap → navigate
    responseListenerRef.current =
      Notifications.addNotificationResponseReceivedListener((response) => {
        const route = resolveRouteFromNotification(response.notification);
        if (route) {
          router.push(route as never);
        }
      });

    return () => {
      if (responseListenerRef.current) {
        Notifications.removeNotificationSubscription(responseListenerRef.current);
      }
    };
  }, []);

  const requestPermission = useCallback(async (): Promise<boolean> => {
    // Request OS permission
    const { status: existingStatus } = await Notifications.getPermissionsAsync();
    let finalStatus = existingStatus;

    if (existingStatus !== 'granted') {
      const { status } = await Notifications.requestPermissionsAsync();
      finalStatus = status;
    }

    if (finalStatus !== 'granted') {
      console.log('[nclaw-notifications] Permission denied');
      return false;
    }

    // Android channel
    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'ɳClaw Notifications',
        importance: Notifications.AndroidImportance.HIGH,
        vibrationPattern: [0, 250, 250, 250],
        lightColor: '#6C3CE1',
      });
    }

    // Acquire push token (Expo Go uses Expo push token; production uses native token)
    try {
      const pushToken = await Notifications.getExpoPushTokenAsync();
      const rawToken = pushToken.data;
      console.log('[nclaw-notifications] Push token registered:', rawToken);
      await SecureStore.setItemAsync(TOKEN_STORE_KEY, rawToken);
      setToken(rawToken);
      setRegistered(true);
      return true;
    } catch (err) {
      console.warn('[nclaw-notifications] Token registration failed:', err);
      // Non-fatal — permission granted but token unavailable (simulator/missing entitlement)
      setRegistered(false);
      return false;
    }
  }, []);

  const updatePref = useCallback(
    async (type: NotificationType, enabled: boolean): Promise<void> => {
      const next: NotificationPrefs = { ...prefs, [type]: enabled };
      setPrefs(next);
      await savePrefs(next);
    },
    [prefs],
  );

  return { registered, token, requestPermission, updatePref, prefs };
}
