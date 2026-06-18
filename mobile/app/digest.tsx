/**
 * DigestViewerScreen — morning AI digest / briefing viewer.
 *
 * Purpose: Render the daily AI-generated digest (feature-spec §1a row "Digest
 *   viewer"). Pulls the most recent digest for the user via the documented digest
 *   GraphQL contract and renders its sections (headline + items). Reached from a
 *   digest push notification or the proactive settings screen.
 *
 * Inputs:  Latest digest via DIGEST_LATEST query (Hasura nclaw_digests).
 * Outputs: Digest headline + sectioned item list.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: proactive.tsx, Hasura nclaw_digests.
 */

import React from 'react';
import { View, Text, ScrollView, Pressable } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { gql, useQuery } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

/** DIGEST_LATEST — most recent digest with its items. */
const DIGEST_LATEST = gql`
  query DigestLatest {
    nclaw_digests(order_by: { created_at: desc }, limit: 1) {
      id
      headline
      created_at
      items {
        id
        title
        body
        category
      }
    }
  }
`;

interface DigestItem {
  id: string;
  title: string;
  body: string;
  category: string | null;
}

interface DigestRow {
  id: string;
  headline: string;
  created_at: string;
  items: DigestItem[];
}

interface DigestData {
  nclaw_digests: DigestRow[];
}

export default function DigestViewerScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [result, refetch] = useQuery<DigestData>({ query: DIGEST_LATEST });
  const digest = result.data?.nclaw_digests?.[0] ?? null;

  const status: ScreenStatus = result.fetching
    ? 'loading'
    : result.error
      ? 'error'
      : !digest
        ? 'empty'
        : 'data';

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
          {t('digest.title', 'Daily Digest')}
        </Text>
      </View>

      <AsyncScreen
        status={status}
        error={result.error ?? null}
        onRetry={() => refetch({ requestPolicy: 'network-only' })}
        onReAuth={() => router.push('/auth/login')}
        testID="digest"
        emptyMessage={t('digest.empty', 'No digest yet. Check back in the morning.')}
      >
        {digest && (
          <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }}>
            <Text className="text-2xl font-bold text-foreground mb-1" style={{ textAlign: dir.textAlign }}>
              {digest.headline}
            </Text>
            <Text className="text-sm text-muted-foreground mb-6" style={{ textAlign: dir.textAlign }}>
              {new Date(digest.created_at).toLocaleDateString()}
            </Text>

            {digest.items.map((item) => (
              <View key={item.id} className="rounded-xl bg-card border border-border p-4 mb-3">
                {item.category && (
                  <View className="self-start px-2 py-0.5 rounded-full bg-primary/10 mb-2">
                    <Text className="text-xs text-primary">{item.category}</Text>
                  </View>
                )}
                <Text className="text-base font-medium text-foreground mb-1" style={{ textAlign: dir.textAlign }}>
                  {item.title}
                </Text>
                <Text className="text-sm text-muted-foreground" style={{ textAlign: dir.textAlign }}>
                  {item.body}
                </Text>
              </View>
            ))}
          </ScrollView>
        )}
      </AsyncScreen>
    </View>
  );
}
