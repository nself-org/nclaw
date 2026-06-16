/**
 * AmbientSettingsToggle — enable/disable ambient sensor context injection.
 *
 * Purpose: Renders a labelled toggle switch on the settings screen that controls
 *          whether motion, location, and battery context is injected into AI prompts.
 *          On first enable, requests each permission with a user-facing explanation
 *          before activating sensor reads. Persists the user's preference in the
 *          async storage settings store so it survives app restarts.
 *
 * Inputs:  None — reads and writes settings store directly.
 * Outputs: Renders one switch row with a description. Requests permissions on
 *          first toggle-on.
 *
 * Constraints:
 *   - Permission request happens once per sensor type; system dialog shows only
 *     if not yet determined. After denial the toggle remains visually on but
 *     location falls back to null — user sees "Location permission denied" notice.
 *   - Toggle off → write enabled: false to store; sensors stop immediately.
 *   - WCAG 2.1 AA: switch has accessibilityLabel + accessibilityHint.
 *   - No direct sensor reads here — this component only controls the enabled flag
 *     that useAmbientContext respects.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: useAmbientContext.ts · T-P3-E4-W2-S3-T10
 */

import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Switch,
  Text,
  View,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Location from 'expo-location';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STORAGE_KEY = '@nclaw/ambient_sensors_enabled';

// ---------------------------------------------------------------------------
// Permission helpers
// ---------------------------------------------------------------------------

async function requestLocationPermission(): Promise<boolean> {
  try {
    const { status: existing } = await Location.getForegroundPermissionsAsync();
    if (existing === 'granted') return true;
    if (existing === 'denied') return false;

    // Show explanation alert before triggering the system prompt.
    await new Promise<void>((resolve) => {
      Alert.alert(
        'Location Access',
        'ɳClaw uses your approximate location to include real-world context in AI responses (e.g. "you appear to be near home"). No location data is stored or transmitted.',
        [{ text: 'Continue', onPress: () => resolve() }],
      );
    });

    const { status } = await Location.requestForegroundPermissionsAsync();
    return status === 'granted';
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export interface AmbientSettingsToggleProps {
  /** Called when the enabled state changes (after permissions handled). */
  onEnabledChange?: (enabled: boolean) => void;
}

export function AmbientSettingsToggle({
  onEnabledChange,
}: AmbientSettingsToggleProps): React.ReactElement {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [locationDenied, setLocationDenied] = useState(false);

  // Load persisted preference on mount.
  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((raw) => {
        const value = raw === 'true';
        setEnabled(value);
        onEnabledChange?.(value);
      })
      .catch(() => {
        // Default to off on storage error.
      })
      .finally(() => setLoading(false));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const handleToggle = useCallback(
    async (value: boolean): Promise<void> => {
      if (value) {
        // Request permissions before activating.
        const locationGranted = await requestLocationPermission();
        setLocationDenied(!locationGranted);
        // Note: motion (react-native-sensors) and battery (expo-battery) don't
        // require explicit permission on iOS/Android — they work on first use.
      } else {
        setLocationDenied(false);
      }

      setEnabled(value);
      onEnabledChange?.(value);
      await AsyncStorage.setItem(STORAGE_KEY, value ? 'true' : 'false').catch(
        () => {
          // Storage write failure is non-critical — continue.
        },
      );
    },
    [onEnabledChange],
  );

  if (loading) {
    return (
      <View className="flex-row items-center justify-between px-4 py-3">
        <Text className="text-base text-neutral-300">Ambient Context</Text>
        <ActivityIndicator size="small" color="#9ca3af" />
      </View>
    );
  }

  return (
    <View>
      <View className="flex-row items-center justify-between px-4 py-3">
        <View className="flex-1 mr-3">
          <Text className="text-base font-medium text-white">
            Ambient Context
          </Text>
          <Text className="text-sm text-neutral-400 mt-0.5">
            Inject motion, location, and battery info into AI prompts
          </Text>
        </View>
        <Switch
          value={enabled}
          onValueChange={(v) => {
            void handleToggle(v);
          }}
          accessibilityLabel="Ambient context sensor injection"
          accessibilityHint={
            enabled
              ? 'Double-tap to disable ambient context in AI prompts'
              : 'Double-tap to enable ambient context in AI prompts'
          }
          trackColor={{ false: '#374151', true: '#6366f1' }}
          thumbColor={enabled ? '#ffffff' : '#9ca3af'}
        />
      </View>
      {locationDenied && (
        <Text className="text-xs text-amber-400 px-4 pb-2">
          Location permission denied — location context will be omitted.
        </Text>
      )}
    </View>
  );
}
