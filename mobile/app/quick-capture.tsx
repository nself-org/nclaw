/**
 * QuickCaptureScreen — fast note/thought capture into ɳClaw memory.
 *
 * Purpose: Friction-free capture surface (feature-spec §1a row "Quick capture").
 *   Used by the home-screen widget and share flow to drop a quick thought straight
 *   into persistent memory via the libnclaw JSI memoryInsert seam, without opening
 *   a full conversation. Presented as a modal.
 *
 * Inputs:  Capture text. NativeNclaw.memoryInsert (JSI) for persistence.
 * Outputs: Single-field capture composer with save + success state.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen (form replaced by success/error).
 *   - All text via t() with inline defaults.
 *   - RTL: layout flips with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: services/homeWidgetService.ts, NativeNclaw.memoryInsert JSI.
 */

import React, { useCallback, useState } from 'react';
import { View, Text, TextInput, Pressable, KeyboardAvoidingView, Platform } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { NativeNclaw } from '@nself/native-bridge';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

export default function QuickCaptureScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('data');
  const [text, setText] = useState('');
  const [error, setError] = useState<Error | null>(null);

  const canSave = text.trim().length > 0;

  const handleSave = useCallback(async () => {
    if (!canSave) return;
    setStatus('loading');
    setError(null);
    try {
      // Persist directly into memory as a captured user note (JSI contract).
      await NativeNclaw.memoryInsert(
        JSON.stringify({ role: 'user', content: text.trim(), source: 'quick_capture' }),
      );
      setStatus('success');
      setTimeout(() => router.back(), 800);
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus('error');
    }
  }, [canSave, text, router]);

  if (status === 'loading' || status === 'success' || status === 'error') {
    return (
      <View className="flex-1 bg-background">
        <AsyncScreen status={status} error={error} onRetry={() => setStatus('data')} testID="quick-capture">
          <View />
        </AsyncScreen>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-background"
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View
        className="px-4 pt-4 pb-2 border-b border-border"
        style={{ flexDirection: dir.flexRow, alignItems: 'center' }}
      >
        <Pressable
          onPress={() => router.back()}
          className="p-2 mr-2"
          accessibilityLabel={t('common.close', 'Close')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 18 }}>✕</Text>
        </Pressable>
        <Text className="flex-1 text-xl font-bold text-foreground" style={{ textAlign: dir.textAlign }}>
          {t('quickCapture.title', 'Quick Capture')}
        </Text>
        <Pressable
          onPress={handleSave}
          disabled={!canSave}
          className={`px-4 py-2 rounded-xl ${canSave ? 'bg-primary' : 'bg-muted'}`}
          accessibilityLabel={t('quickCapture.save', 'Save capture')}
          accessibilityRole="button"
          accessibilityState={{ disabled: !canSave }}
        >
          <Text className={`text-sm font-medium ${canSave ? 'text-primary-foreground' : 'text-muted-foreground'}`}>
            {t('quickCapture.save', 'Save')}
          </Text>
        </Pressable>
      </View>

      <View className="flex-1 p-4">
        <TextInput
          value={text}
          onChangeText={setText}
          placeholder={t('quickCapture.placeholder', 'Capture a thought — ɳClaw will remember it.')}
          placeholderTextColor="#888"
          className="flex-1 text-lg text-foreground"
          style={{ textAlign: dir.textAlign, textAlignVertical: 'top' }}
          accessibilityLabel={t('quickCapture.inputLabel', 'Quick capture note')}
          multiline
          autoFocus
        />
      </View>
    </KeyboardAvoidingView>
  );
}
