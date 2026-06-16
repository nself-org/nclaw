/**
 * NotificationsSettingsScreen — toggle notification preferences.
 *
 * Purpose: Settings sub-screen for configuring push notification types.
 *   Maps to feature-spec S-08 §Notifications group.
 *
 * Inputs:  Current notification preferences from secure store.
 * Outputs: Toggle switches for digest, mention, and sync notifications.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every toggle has accessibilityLabel + accessibilityState.
 *   - RTL: labels flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  Switch,
  ScrollView,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import type { NotificationPreferences } from '../../types/chat';

// ─── Default prefs ────────────────────────────────────────────────────────────

const DEFAULT_PREFS: NotificationPreferences = {
  digestEnabled: true,
  mentionEnabled: true,
  syncEnabled: false,
};

// ─── Toggle row ────────────────────────────────────────────────────────────────

interface ToggleRowProps {
  label: string;
  description: string;
  value: boolean;
  onValueChange: (v: boolean) => void;
}

function ToggleRow({ label, description, value, onValueChange }: ToggleRowProps) {
  const dir = useDirection();
  return (
    <View
      className="flex-row items-center px-4 py-4 border-b border-border"
      style={{ flexDirection: dir.flexRow }}
    >
      <View className="flex-1">
        <Text
          className="text-base font-medium text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {label}
        </Text>
        <Text
          className="text-sm text-muted-foreground mt-0.5"
          style={{ textAlign: dir.textAlign }}
        >
          {description}
        </Text>
      </View>
      <Switch
        value={value}
        onValueChange={onValueChange}
        trackColor={{ false: '#3f3f46', true: '#6C3CE1' }}
        thumbColor={value ? '#fff' : '#9ca3af'}
        accessibilityLabel={label}
        accessibilityRole="switch"
        accessibilityState={{ checked: value }}
        style={dir.isRTL ? { marginRight: 0, marginLeft: 12 } : { marginLeft: 12 }}
      />
    </View>
  );
}

// ─── NotificationsSettingsScreen ─────────────────────────────────────────────

export default function NotificationsSettingsScreen() {
  const { t } = useTranslation();
  const [status] = useState<ScreenStatus>('data');
  const [prefs, setPrefs] = useState<NotificationPreferences>(DEFAULT_PREFS);

  const toggle = useCallback(
    (key: keyof NotificationPreferences) => (value: boolean) => {
      setPrefs((prev) => ({ ...prev, [key]: value }));
      // Persist to secure store — wired in T06
    },
    [],
  );

  return (
    <AsyncScreen status={status} testID="settings-notifications">
      <ScrollView
        className="flex-1 bg-background"
        showsVerticalScrollIndicator={false}
      >
        <View className="rounded-xl mx-4 mt-4 overflow-hidden border border-border">
          <ToggleRow
            label={t('settings.digestNotifications', 'Daily Digest')}
            description={t(
              'settings.digestHint',
              'Receive a daily summary of your conversations.',
            )}
            value={prefs.digestEnabled}
            onValueChange={toggle('digestEnabled')}
          />
          <ToggleRow
            label={t('settings.mentionNotifications', 'Mentions & Replies')}
            description={t(
              'settings.mentionHint',
              'Notify when ɳClaw responds to your messages.',
            )}
            value={prefs.mentionEnabled}
            onValueChange={toggle('mentionEnabled')}
          />
          <ToggleRow
            label={t('settings.syncNotifications', 'Sync Alerts')}
            description={t(
              'settings.syncHint',
              'Notify when background memory sync completes.',
            )}
            value={prefs.syncEnabled}
            onValueChange={toggle('syncEnabled')}
          />
        </View>

        <Text className="text-xs text-muted-foreground text-center px-8 mt-4 mb-8">
          {t(
            'settings.notificationsNote',
            'Notifications require permission granted during onboarding.',
          )}
        </Text>
      </ScrollView>
    </AsyncScreen>
  );
}
