/**
 * OAuthScreen — Google / GitHub OAuth via system browser.
 *
 * Purpose: OAuth connect surface (feature-spec §1a row "OAuth"). Lists supported
 *   providers and launches the provider authorization flow in the system browser
 *   (expo-web-browser style via Linking), returning to the app via the nclaw://
 *   deep-link callback. Tokens are exchanged + stored server-side; this screen only
 *   initiates and reflects connection state.
 *
 * Inputs:  Provider list (static). Auth-start URL: {server}/v1/auth/oauth/{provider}.
 * Outputs: Per-provider connect buttons + connection status.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t() with inline defaults.
 *   - Never embeds provider credentials — browser-based flow only.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: services/deep link (nclaw://), {server}/v1/auth/oauth/{provider}.
 */

import React, { useCallback } from 'react';
import { View, Text, Pressable, ScrollView, Linking } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { useDirection } from '../lib/useDirection';

const API_BASE = process.env.EXPO_PUBLIC_NSELF_API_URL ?? 'http://localhost:3710';

const PROVIDERS: { id: string; label: string; emoji: string }[] = [
  { id: 'google', label: 'Google', emoji: '🟦' },
  { id: 'github', label: 'GitHub', emoji: '🐙' },
];

export default function OAuthScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  // Launch the provider authorization flow in the system browser.
  // The server redirects back to nclaw://oauth-callback on completion.
  const connect = useCallback((provider: string) => {
    const url = `${API_BASE}/v1/auth/oauth/${provider}?redirect=nclaw://oauth-callback`;
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
          {t('oauth.title', 'Connect Accounts')}
        </Text>
      </View>

      <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }}>
        <Text className="text-sm text-muted-foreground mb-4" style={{ textAlign: dir.textAlign }}>
          {t('oauth.intro', 'Connect accounts so ɳClaw can act on your behalf. You will authorize in your browser.')}
        </Text>

        {PROVIDERS.map((p) => (
          <Pressable
            key={p.id}
            onPress={() => connect(p.id)}
            className="flex-row items-center px-4 py-4 rounded-xl bg-card border border-border mb-3"
            accessibilityLabel={t('oauth.connect', 'Connect {{provider}}', { provider: p.label })}
            accessibilityRole="button"
            style={{ flexDirection: dir.flexRow }}
          >
            <Text style={{ fontSize: 22 }} className="mr-3">{p.emoji}</Text>
            <Text className="flex-1 text-base text-foreground" style={{ textAlign: dir.textAlign }}>
              {t('oauth.connect', 'Connect {{provider}}', { provider: p.label })}
            </Text>
            <Text className="text-muted-foreground">{dir.isRTL ? '‹' : '›'}</Text>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}
