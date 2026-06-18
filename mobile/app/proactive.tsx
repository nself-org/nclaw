/**
 * ProactiveSettingsScreen — quiet hours, morning briefing, goal nudges.
 *
 * Purpose: Configure ɳClaw's proactive intelligence (feature-spec §1a row
 *   "Proactive settings"). Toggles for the morning briefing/digest, goal-progress
 *   nudges, and a quiet-hours window during which no proactive pushes are sent.
 *   Persists config in AsyncStorage.
 *
 * Inputs:  morningBriefing, goalNudges toggles · quiet-hours start/end. AsyncStorage.
 * Outputs: Proactive-intelligence config form.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: digest.tsx (briefing viewer), settings/notifications.tsx.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, Pressable, ScrollView, Switch } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';

import { useDirection } from '../lib/useDirection';

const STORAGE_KEY = 'nclaw:proactive';

interface ProactiveConfig {
  morningBriefing: boolean;
  goalNudges: boolean;
  quietStartHour: number;
  quietEndHour: number;
}

const DEFAULT: ProactiveConfig = {
  morningBriefing: true,
  goalNudges: true,
  quietStartHour: 22,
  quietEndHour: 7,
};

/** Format an hour (0–23) as a localized HH:00 label. */
function hourLabel(h: number): string {
  return `${String(h).padStart(2, '0')}:00`;
}

function ToggleRow({
  label,
  hint,
  value,
  onChange,
}: {
  label: string;
  hint: string;
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  const dir = useDirection();
  return (
    <View className="flex-row items-center justify-between py-3 border-b border-border" style={{ flexDirection: dir.flexRow }}>
      <View className="flex-1 mr-3">
        <Text className="text-base text-foreground" style={{ textAlign: dir.textAlign }}>{label}</Text>
        <Text className="text-sm text-muted-foreground" style={{ textAlign: dir.textAlign }}>{hint}</Text>
      </View>
      <Switch value={value} onValueChange={onChange} accessibilityLabel={label} />
    </View>
  );
}

export default function ProactiveSettingsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const [config, setConfig] = useState<ProactiveConfig>(DEFAULT);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((raw) => {
        if (raw) setConfig(JSON.parse(raw) as ProactiveConfig);
      })
      .catch(() => undefined);
  }, []);

  const persist = useCallback(async (next: ProactiveConfig) => {
    setConfig(next);
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }, []);

  const cycleHour = useCallback((field: 'quietStartHour' | 'quietEndHour') => {
    persist({ ...config, [field]: (config[field] + 1) % 24 });
  }, [config, persist]);

  return (
    <View className="flex-1 bg-background">
      <View
        className="px-4 pt-4 pb-2 border-b border-border"
        style={{ flexDirection: dir.flexRow, alignItems: 'center' }}
      >
        <Pressable
          onPress={() => router.back()}
          className="p-2 mr-2"
          accessibilityLabel={t('common.back', 'Go back')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 18 }}>{dir.isRTL ? '→' : '←'}</Text>
        </Pressable>
        <Text className="flex-1 text-xl font-bold text-foreground" style={{ textAlign: dir.textAlign }}>
          {t('proactive.title', 'Proactive')}
        </Text>
      </View>

      <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }}>
        <ToggleRow
          label={t('proactive.morningBriefing', 'Morning briefing')}
          hint={t('proactive.morningBriefingHint', 'A daily AI digest of what matters.')}
          value={config.morningBriefing}
          onChange={(v) => persist({ ...config, morningBriefing: v })}
        />
        <ToggleRow
          label={t('proactive.goalNudges', 'Goal nudges')}
          hint={t('proactive.goalNudgesHint', 'Gentle reminders about your goals.')}
          value={config.goalNudges}
          onChange={(v) => persist({ ...config, goalNudges: v })}
        />

        {/* Quiet hours */}
        <Text className="text-sm font-medium text-foreground mt-6 mb-2" style={{ textAlign: dir.textAlign }}>
          {t('proactive.quietHours', 'Quiet hours')}
        </Text>
        <Text className="text-sm text-muted-foreground mb-3" style={{ textAlign: dir.textAlign }}>
          {t('proactive.quietHoursHint', 'No proactive notifications during this window.')}
        </Text>
        <View className="flex-row gap-3" style={{ flexDirection: dir.flexRow }}>
          <Pressable
            onPress={() => cycleHour('quietStartHour')}
            className="flex-1 py-4 rounded-xl bg-card border border-border items-center"
            accessibilityLabel={t('proactive.quietStart', 'Quiet hours start: {{time}}', { time: hourLabel(config.quietStartHour) })}
            accessibilityRole="button"
          >
            <Text className="text-xs text-muted-foreground">{t('proactive.from', 'From')}</Text>
            <Text className="text-xl font-semibold text-foreground mt-1">{hourLabel(config.quietStartHour)}</Text>
          </Pressable>
          <Pressable
            onPress={() => cycleHour('quietEndHour')}
            className="flex-1 py-4 rounded-xl bg-card border border-border items-center"
            accessibilityLabel={t('proactive.quietEnd', 'Quiet hours end: {{time}}', { time: hourLabel(config.quietEndHour) })}
            accessibilityRole="button"
          >
            <Text className="text-xs text-muted-foreground">{t('proactive.to', 'To')}</Text>
            <Text className="text-xl font-semibold text-foreground mt-1">{hourLabel(config.quietEndHour)}</Text>
          </Pressable>
        </View>
      </ScrollView>
    </View>
  );
}
