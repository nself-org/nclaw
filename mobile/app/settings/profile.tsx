/**
 * ProfileSettingsScreen — edit user display name, avatar, email.
 *
 * Purpose: Settings sub-screen for profile editing.
 *   Maps to feature-spec S-08 §Profile group.
 *
 * Inputs:  Current user profile from auth state.
 * Outputs: Editable form fields for displayName, email, avatar.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every TextInput and Pressable has accessibilityLabel.
 *   - RTL: all layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  Pressable,
  ScrollView,
  Alert,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import type { UserProfile } from '../../types/chat';

// ─── Stub profile ─────────────────────────────────────────────────────────────

const STUB_PROFILE: UserProfile = {
  displayName: '',
  email: '',
};

// ─── ProfileSettingsScreen ────────────────────────────────────────────────────

export default function ProfileSettingsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('data');
  const [profile, setProfile] = useState<UserProfile>(STUB_PROFILE);
  const [isDirty, setIsDirty] = useState(false);

  const handleChange = useCallback(
    (field: keyof UserProfile, value: string) => {
      setProfile((prev) => ({ ...prev, [field]: value }));
      setIsDirty(true);
    },
    [],
  );

  const handleSave = useCallback(async () => {
    setStatus('loading');
    try {
      // Backend mutation wired in T04
      await new Promise((r) => setTimeout(r, 500));
      setIsDirty(false);
      setStatus('success');
      setTimeout(() => {
        setStatus('data');
        router.back();
      }, 1000);
    } catch {
      setStatus('error');
    }
  }, [router]);

  const handleDiscard = useCallback(() => {
    if (isDirty) {
      Alert.alert(
        t('settings.discardTitle', 'Discard changes?'),
        t('settings.discardBody', 'Your unsaved changes will be lost.'),
        [
          { text: t('common.cancel', 'Cancel'), style: 'cancel' },
          {
            text: t('common.discard', 'Discard'),
            style: 'destructive',
            onPress: () => router.back(),
          },
        ],
      );
    } else {
      router.back();
    }
  }, [isDirty, router, t]);

  return (
    <AsyncScreen status={status} testID="settings-profile" onRetry={() => setStatus('data')}>
      <ScrollView
        className="flex-1 bg-background"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ padding: 16 }}
        keyboardShouldPersistTaps="handled"
      >
        {/* Avatar placeholder */}
        <View className="items-center mb-8">
          <View className="w-24 h-24 rounded-full bg-primary/20 items-center justify-center mb-3">
            <Text style={{ fontSize: 40 }}>👤</Text>
          </View>
          <Pressable
            className="px-4 py-2 bg-muted rounded-xl"
            accessibilityLabel={t('settings.changeAvatar', 'Change avatar')}
            accessibilityRole="button"
          >
            <Text className="text-sm text-foreground">
              {t('settings.changeAvatar', 'Change avatar')}
            </Text>
          </Pressable>
        </View>

        {/* Display name */}
        <View className="mb-4">
          <Text
            className="text-sm font-medium text-foreground mb-1"
            style={{ textAlign: dir.textAlign }}
          >
            {t('settings.displayName', 'Display name')}
          </Text>
          <TextInput
            value={profile.displayName}
            onChangeText={(v) => handleChange('displayName', v)}
            placeholder={t('settings.displayNamePlaceholder', 'Your name')}
            placeholderTextColor="#888"
            className="bg-card border border-border rounded-xl px-4 py-3 text-base text-foreground"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('settings.displayName', 'Display name')}
            autoCapitalize="words"
            returnKeyType="next"
          />
        </View>

        {/* Email */}
        <View className="mb-8">
          <Text
            className="text-sm font-medium text-foreground mb-1"
            style={{ textAlign: dir.textAlign }}
          >
            {t('settings.email', 'Email')}
          </Text>
          <TextInput
            value={profile.email}
            onChangeText={(v) => handleChange('email', v)}
            placeholder={t('settings.emailPlaceholder', 'you@example.com')}
            placeholderTextColor="#888"
            className="bg-card border border-border rounded-xl px-4 py-3 text-base text-foreground"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('settings.email', 'Email address')}
            keyboardType="email-address"
            autoCapitalize="none"
            returnKeyType="done"
          />
        </View>

        {/* Actions */}
        <View className="gap-3">
          <Pressable
            onPress={handleSave}
            disabled={!isDirty}
            className={`py-4 rounded-2xl items-center ${isDirty ? 'bg-primary' : 'bg-muted'}`}
            accessibilityLabel={t('common.save', 'Save changes')}
            accessibilityRole="button"
            accessibilityState={{ disabled: !isDirty }}
          >
            <Text
              className={`text-base font-semibold ${isDirty ? 'text-primary-foreground' : 'text-muted-foreground'}`}
            >
              {t('common.save', 'Save changes')}
            </Text>
          </Pressable>
          <Pressable
            onPress={handleDiscard}
            className="py-4 rounded-2xl items-center border border-border"
            accessibilityLabel={t('common.cancel', 'Cancel')}
            accessibilityRole="button"
          >
            <Text className="text-base font-medium text-foreground">
              {t('common.cancel', 'Cancel')}
            </Text>
          </Pressable>
        </View>
      </ScrollView>
    </AsyncScreen>
  );
}
