/**
 * AboutScreen — app version, license, and links.
 *
 * Purpose: Static "About ɳClaw" screen reached from Settings → About & Help.
 *   Shows the app version, MIT license note, and links to docs / privacy / source.
 *   (Not a feature-inventory row, but the Settings hub links here — without this
 *   file the navigation is a dead end.)
 *
 * Inputs:  App version from EXPO_PUBLIC_APP_VERSION.
 * Outputs: Version + license + external links list.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t() with inline defaults.
 *   - External links opened via Linking (never auto-followed).
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: settings/index.tsx.
 */

import React, { useCallback } from 'react';
import { View, Text, Pressable, ScrollView, Linking } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { useDirection } from '../lib/useDirection';

const APP_VERSION = process.env.EXPO_PUBLIC_APP_VERSION ?? '1.1.1';

const LINKS: { id: string; url: string; emoji: string }[] = [
  { id: 'docs', url: 'https://claw.nself.org/docs', emoji: '📖' },
  { id: 'privacy', url: 'https://claw.nself.org/privacy', emoji: '🔒' },
  { id: 'source', url: 'https://github.com/nself-org/nclaw', emoji: '💻' },
];

export default function AboutScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const openLink = useCallback((url: string) => {
    Linking.openURL(url).catch(() => undefined);
  }, []);

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
          {t('about.title', 'About')}
        </Text>
      </View>

      <ScrollView className="flex-1" contentContainerStyle={{ padding: 24, alignItems: 'center' }}>
        <Text className="text-6xl mb-4">🐾</Text>
        <Text className="text-2xl font-bold text-foreground">ɳClaw</Text>
        <Text className="text-sm text-muted-foreground mt-1">
          {t('about.version', 'Version {{version}}', { version: APP_VERSION })}
        </Text>
        <Text className="text-sm text-muted-foreground mt-4 text-center">
          {t('about.tagline', 'Your personal AI with infinite, self-organizing memory. Self-hosted, MIT-licensed, yours.')}
        </Text>

        <View className="w-full mt-8 rounded-xl border border-border overflow-hidden">
          {LINKS.map((link, i) => (
            <Pressable
              key={link.id}
              onPress={() => openLink(link.url)}
              className={`flex-row items-center px-4 py-4 bg-card ${i < LINKS.length - 1 ? 'border-b border-border' : ''}`}
              accessibilityLabel={t(`about.link.${link.id}`, link.id)}
              accessibilityRole="link"
              style={{ flexDirection: dir.flexRow }}
            >
              <Text style={{ fontSize: 20 }} className="mr-3">{link.emoji}</Text>
              <Text className="flex-1 text-base text-foreground" style={{ textAlign: dir.textAlign }}>
                {t(`about.link.${link.id}`, link.id)}
              </Text>
              <Text className="text-muted-foreground">{dir.isRTL ? '‹' : '›'}</Text>
            </Pressable>
          ))}
        </View>

        <Text className="text-xs text-muted-foreground mt-8 text-center">
          {t('about.license', 'MIT License · © nSelf')}
        </Text>
      </ScrollView>
    </View>
  );
}
