/**
 * MemoryScreen — browse and manage all AI-extracted memories (stub).
 *
 * Purpose: Tab placeholder for the memory explorer. Full implementation in T05.
 *   Shows a skeleton/empty state with navigation to the full memory explorer.
 *
 * Inputs:  None — stub screen.
 * Outputs: Memory tab placeholder with call-to-action.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen (defaults to 'data' showing stub).
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T05 (memory recall + full explorer).
 */

import React, { useState } from 'react';
import { View, Text, Pressable } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';

export default function MemoryScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const [status] = useState<ScreenStatus>('data');

  return (
    <View className="flex-1 bg-background">
      {/* Header */}
      <View
        className="px-4 pt-4 pb-2 border-b border-border"
        style={{ flexDirection: dir.flexRow, alignItems: 'center' }}
      >
        <Text
          className="flex-1 text-xl font-bold text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {t('memory.title', 'Memory')}
        </Text>
        <Pressable
          onPress={() => router.push('/search')}
          className="p-2"
          accessibilityLabel={t('memory.search', 'Search memories')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>🔍</Text>
        </Pressable>
      </View>

      <AsyncScreen status={status} testID="memory">
        <View className="flex-1 items-center justify-center px-8">
          <Text className="text-5xl mb-4">🧠</Text>
          <Text className="text-lg font-semibold text-foreground text-center">
            {t('memory.heading', 'Infinite Memory')}
          </Text>
          <Text className="text-sm text-muted-foreground text-center mt-2">
            {t(
              'memory.hint',
              'ɳClaw remembers everything you share. Open the explorer to search semantically.',
            )}
          </Text>
          <Pressable
            onPress={() => router.push('/memory-explorer')}
            className="mt-6 px-6 py-3 bg-primary rounded-xl"
            accessibilityLabel={t('memory.explore', 'Explore memories')}
            accessibilityRole="button"
          >
            <Text className="text-primary-foreground font-medium">
              {t('memory.explore', 'Explore memories')}
            </Text>
          </Pressable>
        </View>
      </AsyncScreen>
    </View>
  );
}
