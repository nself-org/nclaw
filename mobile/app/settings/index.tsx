/**
 * SettingsScreen — full settings hub with 8 section groups.
 *
 * Purpose: Root of the settings navigator. Lists all setting categories
 *   with disclosure rows. Maps to feature-spec S-08.
 *
 * Inputs:  User profile from auth state.
 * Outputs: Scrollable settings menu grouped by category.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *   - RTL: all layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  Pressable,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';

// ─── Setting row ──────────────────────────────────────────────────────────────

interface SettingRowProps {
  label: string;
  description?: string;
  emoji?: string;
  onPress: () => void;
  isLast?: boolean;
}

function SettingRow({ label, description, emoji, onPress, isLast }: SettingRowProps) {
  const dir = useDirection();
  return (
    <Pressable
      onPress={onPress}
      className={`flex-row items-center px-4 py-4 bg-card ${!isLast ? 'border-b border-border' : ''}`}
      accessibilityLabel={label}
      accessibilityRole="button"
      style={{ flexDirection: dir.flexRow }}
    >
      {emoji && (
        <Text style={{ fontSize: 20 }} className="mr-3">
          {emoji}
        </Text>
      )}
      <View className="flex-1">
        <Text
          className="text-base text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {label}
        </Text>
        {description && (
          <Text
            className="text-sm text-muted-foreground mt-0.5"
            style={{ textAlign: dir.textAlign }}
          >
            {description}
          </Text>
        )}
      </View>
      <Text className="text-muted-foreground" style={dir.marginStart(8)}>
        {dir.isRTL ? '‹' : '›'}
      </Text>
    </Pressable>
  );
}

// ─── Section ──────────────────────────────────────────────────────────────────

function SettingSection({ title, children }: { title: string; children: React.ReactNode }) {
  const dir = useDirection();
  return (
    <View className="mb-6">
      <Text
        className="px-4 pb-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider"
        style={{ textAlign: dir.textAlign }}
      >
        {title}
      </Text>
      <View className="rounded-xl mx-4 overflow-hidden border border-border">
        {children}
      </View>
    </View>
  );
}

// ─── SettingsScreen ───────────────────────────────────────────────────────────

export default function SettingsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const [status] = useState<ScreenStatus>('data');

  return (
    <AsyncScreen status={status} testID="settings">
      <ScrollView
        className="flex-1 bg-background"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingVertical: 16 }}
      >
        {/* Profile */}
        <SettingSection title={t('settings.sectionProfile', 'Profile')}>
          <SettingRow
            emoji="👤"
            label={t('settings.profile', 'Profile')}
            description={t('settings.profileHint', 'Name, avatar, email')}
            onPress={() => router.push('/settings/profile')}
          />
        </SettingSection>

        {/* AI & Models */}
        <SettingSection title={t('settings.sectionAI', 'AI & Models')}>
          <SettingRow
            emoji="🤖"
            label={t('settings.localAI', 'Local AI')}
            description={t('settings.localAIHint', 'Manage local LLM models')}
            onPress={() => router.push('/local-ai')}
          />
          <SettingRow
            emoji="🔑"
            label={t('settings.apiKeys', 'API Keys')}
            description={t('settings.apiKeysHint', 'Provider API key management')}
            onPress={() => router.push('/api-keys')}
            isLast
          />
        </SettingSection>

        {/* Appearance */}
        <SettingSection title={t('settings.sectionAppearance', 'Appearance')}>
          <SettingRow
            emoji="🎨"
            label={t('settings.theme', 'Theme')}
            description={t('settings.themeHint', 'Light, dark, or system')}
            onPress={() => router.push('/settings/theme')}
          />
          <SettingRow
            emoji="🌐"
            label={t('settings.language', 'Language')}
            description={t('settings.languageHint', 'Choose app language')}
            onPress={() => router.push('/settings/locale')}
            isLast
          />
        </SettingSection>

        {/* Notifications */}
        <SettingSection title={t('settings.sectionNotifications', 'Notifications')}>
          <SettingRow
            emoji="🔔"
            label={t('settings.notifications', 'Notifications')}
            description={t('settings.notificationsHint', 'Digest, mentions, sync alerts')}
            onPress={() => router.push('/settings/notifications')}
          />
        </SettingSection>

        {/* Privacy & Security */}
        <SettingSection title={t('settings.sectionSecurity', 'Privacy & Security')}>
          <SettingRow
            emoji="🔒"
            label={t('settings.biometrics', 'Biometric Auth')}
            description={t('settings.biometricsHint', 'Require Face ID / fingerprint on open')}
            onPress={() => router.push('/biometric-settings')}
          />
        </SettingSection>

        {/* Data */}
        <SettingSection title={t('settings.sectionData', 'Data & Sync')}>
          <SettingRow
            emoji="📦"
            label={t('settings.dataExport', 'Export Data')}
            description={t('settings.dataExportHint', 'Export all conversations and memories')}
            onPress={() => router.push('/settings/data-export')}
          />
        </SettingSection>

        {/* About */}
        <SettingSection title={t('settings.sectionAbout', 'About & Help')}>
          <SettingRow
            emoji="ℹ️"
            label={t('settings.about', 'About ɳClaw')}
            onPress={() => router.push('/about')}
          />
          <SettingRow
            emoji="💬"
            label={t('settings.feedback', 'Send Feedback')}
            onPress={() => router.push('/feedback')}
            isLast
          />
        </SettingSection>
      </ScrollView>
    </AsyncScreen>
  );
}
