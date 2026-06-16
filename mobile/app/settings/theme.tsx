/**
 * ThemeSettingsScreen — select display theme (light / dark / system).
 *
 * Purpose: Settings sub-screen for appearance theme selection.
 * Inputs:  Current theme from app settings.
 * Outputs: Radio-style list with 3 theme options.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every option has accessibilityLabel + accessibilityState.checked.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useState } from 'react';
import {
  View,
  Text,
  Pressable,
  ScrollView,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import type { ThemePreference } from '../../types/chat';

interface ThemeOption {
  value: ThemePreference;
  labelKey: string;
  emoji: string;
}

const THEME_OPTIONS: ThemeOption[] = [
  { value: 'light',  labelKey: 'settings.themeLight',  emoji: '☀️' },
  { value: 'dark',   labelKey: 'settings.themeDark',   emoji: '🌙' },
  { value: 'system', labelKey: 'settings.themeSystem', emoji: '📱' },
];

export default function ThemeSettingsScreen() {
  const { t } = useTranslation();
  const dir = useDirection();
  const [status] = useState<ScreenStatus>('data');
  const [selected, setSelected] = useState<ThemePreference>('system');

  return (
    <AsyncScreen status={status} testID="settings-theme">
      <ScrollView
        className="flex-1 bg-background"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ padding: 16 }}
      >
        <View className="rounded-xl overflow-hidden border border-border">
          {THEME_OPTIONS.map((option, index) => (
            <Pressable
              key={option.value}
              onPress={() => { setSelected(option.value); /* persist wired in T04 */ }}
              className={`flex-row items-center px-4 py-4 bg-card ${
                index < THEME_OPTIONS.length - 1 ? 'border-b border-border' : ''
              }`}
              accessibilityLabel={t(option.labelKey, option.value)}
              accessibilityRole="radio"
              accessibilityState={{ checked: selected === option.value }}
              style={{ flexDirection: dir.flexRow }}
            >
              <Text style={{ fontSize: 22 }} className="mr-3">
                {option.emoji}
              </Text>
              <Text
                className="flex-1 text-base text-foreground"
                style={{ textAlign: dir.textAlign }}
              >
                {t(option.labelKey, option.value)}
              </Text>
              {selected === option.value && (
                <Text className="text-primary text-base">✓</Text>
              )}
            </Pressable>
          ))}
        </View>
      </ScrollView>
    </AsyncScreen>
  );
}
