/**
 * DataExportScreen — export all conversations and memories.
 *
 * Purpose: Allows the user to trigger a full data export (JSON).
 *   Maps to feature-spec S-08 §Data & Sync group.
 *
 * Inputs:  None.
 * Outputs: Export action button + status.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  ScrollView,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';

export default function DataExportScreen() {
  const { t } = useTranslation();
  const dir = useDirection();
  const [status, setStatus] = useState<ScreenStatus>('data');

  const handleExport = useCallback(async () => {
    setStatus('loading');
    try {
      // Export API call wired in T04
      await new Promise((r) => setTimeout(r, 1000));
      setStatus('success');
      setTimeout(() => setStatus('data'), 2000);
    } catch {
      setStatus('error');
    }
  }, []);

  return (
    <AsyncScreen
      status={status}
      testID="settings-data-export"
      onRetry={() => setStatus('data')}
    >
      <ScrollView
        className="flex-1 bg-background"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ padding: 16 }}
      >
        <View className="items-center mb-8 pt-8">
          <Text style={{ fontSize: 48 }}>📦</Text>
          <Text
            className="text-xl font-semibold text-foreground mt-4 text-center"
            style={{ textAlign: dir.textAlign }}
          >
            {t('dataExport.title', 'Export Your Data')}
          </Text>
          <Text
            className="text-sm text-muted-foreground mt-2 text-center"
            style={{ textAlign: dir.textAlign }}
          >
            {t(
              'dataExport.description',
              'Download all your conversations, memories, and settings as a JSON archive.',
            )}
          </Text>
        </View>

        {/* What's included */}
        <View className="bg-card rounded-xl border border-border p-4 mb-6">
          <Text
            className="text-sm font-semibold text-foreground mb-3"
            style={{ textAlign: dir.textAlign }}
          >
            {t('dataExport.includes', "What's included")}
          </Text>
          {[
            t('dataExport.conversations', 'All conversations and messages'),
            t('dataExport.memories', 'All extracted memories'),
            t('dataExport.settings', 'Settings and preferences'),
          ].map((item) => (
            <View
              key={item}
              className="flex-row items-center mb-2"
              style={{ flexDirection: dir.flexRow }}
            >
              <Text className="text-primary mr-2">✓</Text>
              <Text className="text-sm text-foreground" style={{ textAlign: dir.textAlign }}>
                {item}
              </Text>
            </View>
          ))}
        </View>

        {/* Export button */}
        <Pressable
          onPress={handleExport}
          className="py-4 bg-primary rounded-2xl items-center"
          accessibilityLabel={t('dataExport.exportButton', 'Export all data')}
          accessibilityRole="button"
        >
          <Text className="text-base font-semibold text-primary-foreground">
            {t('dataExport.exportButton', 'Export all data')}
          </Text>
        </Pressable>

        <Text className="text-xs text-muted-foreground text-center mt-4">
          {t('dataExport.note', 'Export may take a few minutes for large datasets.')}
        </Text>
      </ScrollView>
    </AsyncScreen>
  );
}
