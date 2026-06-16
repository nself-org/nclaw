/**
 * nclaw/mobile — Home Widget Service
 *
 * Purpose: Manages home screen widget data by writing to shared storage (UserDefaults on iOS,
 *          SharedPreferences on Android) after each conversation completes. Widgets read from
 *          this shared storage to display the last AI summary and trigger quick-capture deep links.
 * Inputs:  Conversation summary after chat message completion.
 * Outputs: Writes lastSummary + captureDeepLink to shared app-group storage.
 * Constraints:
 *   - iOS UserDefaults requires app group identifier (e.g., "group.org.nself.nclaw.widget").
 *   - Android SharedPreferences uses context and preference file name.
 *   - Widget tap calls nclaw://capture deep link (handled in T04 deep link router).
 *   - Data writes are fire-and-forget; widget reads cached data until next update.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn home-widget)
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { Platform } from 'react-native';

const WIDGET_DATA_KEY = 'nclaw_widget_data';
const APP_GROUP_IDENTIFIER = 'group.org.nself.nclaw.widget';
const ANDROID_PREFS_KEY = 'org.nself.nclaw.widget';

export interface WidgetData {
  lastSummary: string;
  captureDeepLink: string;
  updatedAt: number; // ISO timestamp
}

/**
 * Write widget data to shared storage after a conversation completes.
 *
 * Inputs:
 *   summary: Last AI message or auto-generated summary (e.g., "Last chat: What is AI?")
 *   captureUrl: Deep link (e.g., "nclaw://capture")
 * Outputs:
 *   Writes to UserDefaults (iOS) or SharedPreferences (Android).
 *   Fire-and-forget; errors logged but do not block main chat flow.
 * Constraints:
 *   - Call after each message completion (not on every keystroke).
 *   - Summary should be <80 chars for widget display.
 */
export async function updateWidgetData(summary: string, captureUrl: string = 'nclaw://capture'): Promise<void> {
  try {
    const widgetData: WidgetData = {
      lastSummary: summary,
      captureDeepLink: captureUrl,
      updatedAt: Date.now(),
    };

    if (Platform.OS === 'ios') {
      // iOS: Write to app group UserDefaults (requires linked shared entitlement)
      // Native bridge call (wired via react-native-shared-preferences or custom native module)
      await writeToIOSUserDefaults(widgetData);
    } else if (Platform.OS === 'android') {
      // Android: Write to SharedPreferences
      // Native bridge call (wired via react-native-shared-preferences or custom module)
      await writeToAndroidSharedPreferences(widgetData);
    }

    // Fallback: Write to AsyncStorage (for testing, not used by widget on device)
    await AsyncStorage.setItem(WIDGET_DATA_KEY, JSON.stringify(widgetData));
  } catch (error) {
    // Log but do not re-throw; widget update failure should not break chat.
    console.error('[homeWidgetService] Failed to update widget data:', error);
  }
}

/**
 * Read widget data from shared storage (for debugging/validation in app).
 * In production, widgets read directly from native storage; this is for app-side inspection only.
 */
export async function readWidgetData(): Promise<WidgetData | null> {
  try {
    const cached = await AsyncStorage.getItem(WIDGET_DATA_KEY);
    if (!cached) return null;
    return JSON.parse(cached) as WidgetData;
  } catch (error) {
    console.error('[homeWidgetService] Failed to read widget data:', error);
    return null;
  }
}

/**
 * Clear widget data (e.g., on logout or app uninstall).
 */
export async function clearWidgetData(): Promise<void> {
  try {
    await AsyncStorage.removeItem(WIDGET_DATA_KEY);
    if (Platform.OS === 'ios') {
      await clearIOSUserDefaults();
    } else if (Platform.OS === 'android') {
      await clearAndroidSharedPreferences();
    }
  } catch (error) {
    console.error('[homeWidgetService] Failed to clear widget data:', error);
  }
}

/**
 * --- Native Bridge Stubs (to be wired to Expo/React-Native native modules) ---
 *
 * These functions are placeholders for native bridge calls. In production:
 *   - iOS: Use a custom RN module or react-native-shared-preferences (if available for app groups).
 *   - Android: Use react-native-shared-preferences or native RN module.
 *
 * For MVP, these can be no-ops; widget will read empty/cached data until bridge is wired.
 */

async function writeToIOSUserDefaults(data: WidgetData): Promise<void> {
  // TODO: Wire to native iOS module (RNSharedPreferences or custom NSUserDefaults bridge).
  // Stub: logs intent but does not persist to UserDefaults yet.
  console.log('[homeWidgetService] iOS: would write to UserDefaults', { data, appGroup: APP_GROUP_IDENTIFIER });
}

async function writeToAndroidSharedPreferences(data: WidgetData): Promise<void> {
  // TODO: Wire to native Android module (RNSharedPreferences or custom SharedPreferences bridge).
  // Stub: logs intent but does not persist to SharedPreferences yet.
  console.log('[homeWidgetService] Android: would write to SharedPreferences', { data, prefsKey: ANDROID_PREFS_KEY });
}

async function clearIOSUserDefaults(): Promise<void> {
  console.log('[homeWidgetService] iOS: would clear UserDefaults');
}

async function clearAndroidSharedPreferences(): Promise<void> {
  console.log('[homeWidgetService] Android: would clear SharedPreferences');
}
