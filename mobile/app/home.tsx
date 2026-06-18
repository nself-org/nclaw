/**
 * HomeScreen — dashboard entry shell with greeting + quick actions.
 *
 * Purpose: Home / dashboard surface (feature-spec §1a row "Home / dashboard").
 *   A personalized greeting header plus quick-action tiles into the core surfaces
 *   (chat, voice, memory, quick capture, digest). The tab app boots into chat;
 *   this dashboard is the deep-link target for nclaw://home and a richer landing.
 *
 * Inputs:  Auth state (display name) from @nself/auth-core.
 * Outputs: Greeting + quick-action grid.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t() with inline defaults.
 *   - Every Pressable has accessibilityLabel.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: GreetingHeader (feature-inventory §1e), deep link nclaw://home.
 */

import React, { useMemo } from 'react';
import { View, Text, Pressable, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useAuth } from '@nself/auth-core';

import { useDirection } from '../lib/useDirection';

/** Time-of-day greeting key. */
function greetingKey(hour: number): 'morning' | 'afternoon' | 'evening' {
  if (hour < 12) return 'morning';
  if (hour < 18) return 'afternoon';
  return 'evening';
}

interface QuickAction {
  id: string;
  emoji: string;
  route: string;
}

const QUICK_ACTIONS: QuickAction[] = [
  { id: 'chat', emoji: '💬', route: '/(tabs)/chat' },
  { id: 'voice', emoji: '🎙️', route: '/voice-input' },
  { id: 'capture', emoji: '⚡', route: '/quick-capture' },
  { id: 'memory', emoji: '🧠', route: '/memory-explorer' },
  { id: 'digest', emoji: '📰', route: '/digest' },
  { id: 'projects', emoji: '📁', route: '/projects' },
];

export default function HomeScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const auth = useAuth();

  const displayName =
    auth.status === 'authenticated' && 'user' in auth && auth.user
      ? (auth.user as { displayName?: string; name?: string }).displayName ??
        (auth.user as { name?: string }).name ??
        ''
      : '';

  const greeting = useMemo(() => {
    const key = greetingKey(new Date().getHours());
    const base = t(`home.greeting.${key}`, key === 'morning' ? 'Good morning' : key === 'afternoon' ? 'Good afternoon' : 'Good evening');
    return displayName ? `${base}, ${displayName}` : base;
  }, [displayName, t]);

  return (
    <ScrollView className="flex-1 bg-background" contentContainerStyle={{ padding: 16 }}>
      {/* Greeting header */}
      <View className="mb-8 mt-4">
        <Text className="text-3xl font-bold text-foreground" style={{ textAlign: dir.textAlign }}>
          {greeting}
        </Text>
        <Text className="text-base text-muted-foreground mt-1" style={{ textAlign: dir.textAlign }}>
          {t('home.subtitle', 'What can ɳClaw help you with today?')}
        </Text>
      </View>

      {/* Quick actions grid */}
      <View className="flex-row flex-wrap" style={{ flexDirection: dir.flexRow, marginHorizontal: -6 }}>
        {QUICK_ACTIONS.map((action) => (
          <View key={action.id} style={{ width: '50%', padding: 6 }}>
            <Pressable
              onPress={() => router.push(action.route)}
              className="rounded-2xl bg-card border border-border p-5 items-center"
              accessibilityLabel={t(`home.action.${action.id}`, action.id)}
              accessibilityRole="button"
            >
              <Text style={{ fontSize: 32 }} className="mb-2">{action.emoji}</Text>
              <Text className="text-base font-medium text-foreground text-center">
                {t(`home.action.${action.id}`, action.id)}
              </Text>
            </Pressable>
          </View>
        ))}
      </View>
    </ScrollView>
  );
}
