/**
 * FeedbackScreen — in-app feedback submission.
 *
 * Purpose: In-app feedback form (feature-spec §1a row "Feedback"). Lets the user
 *   pick a category (bug / idea / other), write a message, and submit it to the
 *   server feedback endpoint. Reached from Settings → About & Help → Send Feedback.
 *
 * Inputs:  Category + message text. POST {server}/v1/feedback (documented contract).
 * Outputs: Feedback form with category chips and submit action.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen (form is replaced by success/error state).
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: settings/index.tsx · POST {server}/v1/feedback.
 */

import React, { useCallback, useState } from 'react';
import { View, Text, TextInput, Pressable, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

type FeedbackCategory = 'bug' | 'idea' | 'other';

const CATEGORIES: { key: FeedbackCategory; emoji: string }[] = [
  { key: 'bug', emoji: '🐞' },
  { key: 'idea', emoji: '💡' },
  { key: 'other', emoji: '💬' },
];

const FEEDBACK_URL = `${process.env.EXPO_PUBLIC_NSELF_API_URL ?? 'http://localhost:3710'}/v1/feedback`;

export default function FeedbackScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('data');
  const [category, setCategory] = useState<FeedbackCategory>('idea');
  const [message, setMessage] = useState('');
  const [error, setError] = useState<Error | null>(null);

  const canSubmit = message.trim().length >= 3;

  const handleSubmit = useCallback(async () => {
    if (!canSubmit) return;
    setStatus('loading');
    setError(null);
    try {
      const res = await fetch(FEEDBACK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ category, message: message.trim() }),
      });
      if (res.status === 429) {
        setStatus('rate-limited');
        return;
      }
      if (!res.ok) throw new Error(t('feedback.failed', 'Could not send feedback. Try again.'));
      setStatus('success');
      setTimeout(() => router.back(), 1000);
    } catch (err) {
      const isNetwork = err instanceof TypeError;
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus(isNetwork ? 'offline' : 'error');
    }
  }, [canSubmit, category, message, router, t]);

  if (status !== 'data') {
    return (
      <View className="flex-1 bg-background">
        <AsyncScreen status={status} error={error} onRetry={() => setStatus('data')} testID="feedback">
          <View />
        </AsyncScreen>
      </View>
    );
  }

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
          {t('feedback.title', 'Send Feedback')}
        </Text>
      </View>

      <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
        {/* Category chips */}
        <Text className="text-sm font-medium text-foreground mb-2" style={{ textAlign: dir.textAlign }}>
          {t('feedback.category', 'Category')}
        </Text>
        <View className="flex-row gap-2 mb-6" style={{ flexDirection: dir.flexRow }}>
          {CATEGORIES.map((c) => {
            const active = category === c.key;
            return (
              <Pressable
                key={c.key}
                onPress={() => setCategory(c.key)}
                className={`flex-1 py-3 rounded-xl items-center ${active ? 'bg-primary' : 'bg-muted'}`}
                accessibilityLabel={t(`feedback.cat.${c.key}`, c.key)}
                accessibilityRole="button"
                accessibilityState={{ selected: active }}
              >
                <Text className={`text-sm font-medium ${active ? 'text-primary-foreground' : 'text-muted-foreground'}`}>
                  {c.emoji} {t(`feedback.cat.${c.key}`, c.key)}
                </Text>
              </Pressable>
            );
          })}
        </View>

        {/* Message */}
        <Text className="text-sm font-medium text-foreground mb-2" style={{ textAlign: dir.textAlign }}>
          {t('feedback.message', 'Your feedback')}
        </Text>
        <TextInput
          value={message}
          onChangeText={setMessage}
          placeholder={t('feedback.placeholder', 'Tell us what is on your mind...')}
          placeholderTextColor="#888"
          className="bg-card border border-border rounded-xl px-4 py-3 text-base text-foreground min-h-32"
          style={{ textAlign: dir.textAlign, textAlignVertical: 'top' }}
          accessibilityLabel={t('feedback.message', 'Your feedback')}
          multiline
        />

        <Pressable
          onPress={handleSubmit}
          disabled={!canSubmit}
          className={`mt-6 py-4 rounded-2xl items-center ${canSubmit ? 'bg-primary' : 'bg-muted'}`}
          accessibilityLabel={t('feedback.submit', 'Submit feedback')}
          accessibilityRole="button"
          accessibilityState={{ disabled: !canSubmit }}
        >
          <Text className={`text-base font-semibold ${canSubmit ? 'text-primary-foreground' : 'text-muted-foreground'}`}>
            {t('feedback.submit', 'Submit')}
          </Text>
        </Pressable>
      </ScrollView>
    </View>
  );
}
