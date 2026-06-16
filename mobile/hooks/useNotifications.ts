/**
 * Purpose: Manage push notification preferences for ɳClaw mobile.
 *   Loads and persists per-type notification toggles (insight alert / memory summary /
 *   topic suggestion) via expo-secure-store. Exposes permission status and a
 *   requestPermission() helper so settings screens can surface the current state.
 *
 * Inputs: None — reads prefs from SecureStore on mount.
 * Outputs:
 *   { prefs, permissionStatus, isLoading, updatePref, requestPermission }
 *   - prefs: NotificationPreferences (digestEnabled / mentionEnabled / syncEnabled)
 *   - permissionStatus: 'granted' | 'denied' | 'undetermined'
 *   - isLoading: true while initial SecureStore read is in flight
 *   - updatePref: (key, value) => Promise<void> — toggle one pref and persist
 *   - requestPermission: () => Promise<boolean> — request OS permission
 *
 * Constraints:
 *   - Prefs default to: digest ON, mention ON, sync OFF (matches NotificationPreferences defaults).
 *   - SecureStore failures are swallowed — falls back to defaults, never throws.
 *   - requestPermission is idempotent; no-ops when already granted.
 *   - No crash when called in environments without a real push token (simulator).
 *
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-push-preferences
 * Cross-ref: T-P3-E4-W2-S3-T06 (push notifications ticket), pushNotificationService.ts
 */
import { useCallback, useEffect, useState } from 'react';
import * as Notifications from 'expo-notifications';
import * as SecureStore from 'expo-secure-store';

import type { NotificationPreferences } from '../types/chat';

// ─── Constants ────────────────────────────────────────────────────────────────

const NOTIFICATION_PREFS_KEY = 'nclaw_notification_prefs_v1';

/** Default preferences: digest + mention on, sync off. */
const DEFAULT_PREFS: NotificationPreferences = {
  digestEnabled: true,   // "memory summary" notifications
  mentionEnabled: true,  // "insight alert" notifications
  syncEnabled: false,    // "topic suggestion" notifications
};

// ─── Notification type mapping (ticket scope → pref key) ─────────────────────
// insight alert      → mentionEnabled
// memory summary     → digestEnabled
// topic suggestion   → syncEnabled

// ─── Storage helpers ──────────────────────────────────────────────────────────

async function loadPrefs(): Promise<NotificationPreferences> {
  try {
    const raw = await SecureStore.getItemAsync(NOTIFICATION_PREFS_KEY);
    if (!raw) return { ...DEFAULT_PREFS };
    const parsed = JSON.parse(raw) as Partial<NotificationPreferences>;
    return {
      digestEnabled: parsed.digestEnabled ?? DEFAULT_PREFS.digestEnabled,
      mentionEnabled: parsed.mentionEnabled ?? DEFAULT_PREFS.mentionEnabled,
      syncEnabled: parsed.syncEnabled ?? DEFAULT_PREFS.syncEnabled,
    };
  } catch {
    return { ...DEFAULT_PREFS };
  }
}

async function savePrefs(prefs: NotificationPreferences): Promise<void> {
  try {
    await SecureStore.setItemAsync(NOTIFICATION_PREFS_KEY, JSON.stringify(prefs));
  } catch {
    // Non-fatal — pref will revert to default on next cold start.
    console.warn('[useNotifications] Failed to persist notification prefs');
  }
}

// ─── Permission helpers ───────────────────────────────────────────────────────

async function getCurrentPermissionStatus(): Promise<Notifications.PermissionStatus> {
  try {
    const { status } = await Notifications.getPermissionsAsync();
    return status;
  } catch {
    return Notifications.PermissionStatus.UNDETERMINED;
  }
}

// ─── Types ────────────────────────────────────────────────────────────────────

export interface UseNotificationsReturn {
  /** Current notification preferences (persisted across app restarts). */
  prefs: NotificationPreferences;
  /** OS-level push notification permission status. */
  permissionStatus: Notifications.PermissionStatus;
  /** True while initial SecureStore read + permission check are in flight. */
  isLoading: boolean;
  /**
   * Toggle a single notification preference and persist it immediately.
   * @param key  One of 'digestEnabled' | 'mentionEnabled' | 'syncEnabled'
   * @param value  New boolean value
   */
  updatePref: (key: keyof NotificationPreferences, value: boolean) => Promise<void>;
  /**
   * Request OS push notification permission.
   * No-ops when already granted. Returns true if granted after the call.
   */
  requestPermission: () => Promise<boolean>;
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * useNotifications — notification preferences + permission manager.
 *
 * Usage (notifications settings screen):
 *   const { prefs, permissionStatus, isLoading, updatePref } = useNotifications();
 *
 * Notification type → pref key mapping:
 *   - Insight alert     → mentionEnabled
 *   - Memory summary    → digestEnabled
 *   - Topic suggestion  → syncEnabled
 */
export function useNotifications(): UseNotificationsReturn {
  const [prefs, setPrefs] = useState<NotificationPreferences>({ ...DEFAULT_PREFS });
  const [permissionStatus, setPermissionStatus] = useState<Notifications.PermissionStatus>(
    Notifications.PermissionStatus.UNDETERMINED,
  );
  const [isLoading, setIsLoading] = useState(true);

  // ── Load prefs + permission status on mount ───────────────────────────────
  useEffect(() => {
    let mounted = true;

    async function init() {
      const [loaded, status] = await Promise.all([
        loadPrefs(),
        getCurrentPermissionStatus(),
      ]);
      if (!mounted) return;
      setPrefs(loaded);
      setPermissionStatus(status);
      setIsLoading(false);
    }

    init();
    return () => {
      mounted = false;
    };
  }, []);

  // ── updatePref: toggle one key and persist ────────────────────────────────
  const updatePref = useCallback(
    async (key: keyof NotificationPreferences, value: boolean) => {
      const updated = { ...prefs, [key]: value };
      setPrefs(updated);
      await savePrefs(updated);
    },
    [prefs],
  );

  // ── requestPermission: idempotent OS permission request ───────────────────
  const requestPermission = useCallback(async (): Promise<boolean> => {
    try {
      // No-op if already granted
      if (permissionStatus === Notifications.PermissionStatus.GRANTED) return true;

      const { status } = await Notifications.requestPermissionsAsync({
        ios: {
          allowAlert: true,
          allowBadge: true,
          allowSound: true,
        },
      });
      setPermissionStatus(status);
      return status === Notifications.PermissionStatus.GRANTED;
    } catch {
      console.warn('[useNotifications] Permission request failed');
      return false;
    }
  }, [permissionStatus]);

  return { prefs, permissionStatus, isLoading, updatePref, requestPermission };
}
