/**
 * ApiUsageScreen — 30-day per-model usage + cost breakdown.
 *
 * Purpose: Per-provider/model usage view (feature-spec §1a row "API Usage").
 *   Shows the last 30 days of usage grouped by model: request count, token totals,
 *   and cost, via the documented per-model usage GraphQL contract.
 *
 * Inputs:  Per-model rows via API_USAGE_BY_MODEL query (Hasura nclaw_usage_by_model view).
 * Outputs: Ranked per-model usage cards.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: usage.tsx (period totals), Hasura nclaw_usage_by_model.
 */

import React from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { gql, useQuery } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

/**
 * API_USAGE_BY_MODEL — 30-day usage grouped by model.
 * Mirrors the Hasura `nclaw_usage_by_model` aggregate view contract.
 */
const API_USAGE_BY_MODEL = gql`
  query ApiUsageByModel {
    nclaw_usage_by_model(order_by: { cost_usd: desc }) {
      model
      provider
      request_count
      total_tokens
      cost_usd
    }
  }
`;

interface ModelUsageRow {
  model: string;
  provider: string;
  request_count: number;
  total_tokens: number;
  cost_usd: number;
}

interface ApiUsageData {
  nclaw_usage_by_model: ModelUsageRow[];
}

export default function ApiUsageScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [result, refetch] = useQuery<ApiUsageData>({ query: API_USAGE_BY_MODEL });
  const rows = result.data?.nclaw_usage_by_model ?? [];

  const status: ScreenStatus = result.fetching
    ? 'loading'
    : result.error
      ? 'error'
      : rows.length === 0
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
          {t('apiUsage.title', 'API Usage')}
        </Text>
      </View>

      <AsyncScreen
        status={status}
        error={result.error ?? null}
        onRetry={() => refetch({ requestPolicy: 'network-only' })}
        onReAuth={() => router.push('/auth/login')}
        testID="api-usage"
        emptyMessage={t('apiUsage.empty', 'No model usage in the last 30 days')}
      >
        <FlatList
          data={rows}
          keyExtractor={(r) => `${r.provider}:${r.model}`}
          contentContainerStyle={{ padding: 16 }}
          ListHeaderComponent={
            <Text className="text-sm text-muted-foreground mb-3" style={{ textAlign: dir.textAlign }}>
              {t('apiUsage.subtitle', 'Last 30 days, by model')}
            </Text>
          }
          renderItem={({ item }) => (
            <View
              className="rounded-xl bg-card border border-border p-4 mb-3"
              accessibilityLabel={`${item.model} (${item.provider}): ${item.request_count} ${t('apiUsage.requests', 'requests')}, ${item.total_tokens} ${t('usage.tokens', 'tokens')}, $${item.cost_usd.toFixed(2)}`}
            >
              <View className="flex-row items-center mb-2" style={{ flexDirection: dir.flexRow }}>
                <Text className="flex-1 text-base font-medium text-foreground" style={{ textAlign: dir.textAlign }}>
                  {item.model}
                </Text>
                <View className="px-2 py-0.5 rounded-full bg-primary/10">
                  <Text className="text-xs text-primary">{item.provider}</Text>
                </View>
              </View>
              <View className="flex-row justify-between" style={{ flexDirection: dir.flexRow }}>
                <Text className="text-sm text-muted-foreground">
                  {item.request_count} {t('apiUsage.requests', 'reqs')}
                </Text>
                <Text className="text-sm text-muted-foreground">
                  {item.total_tokens.toLocaleString()} {t('usage.tokens', 'tok')}
                </Text>
                <Text className="text-sm font-medium text-foreground">${item.cost_usd.toFixed(2)}</Text>
              </View>
            </View>
          )}
          showsVerticalScrollIndicator={false}
          accessibilityLabel={t('apiUsage.listLabel', 'Usage by model')}
        />
      </AsyncScreen>
    </View>
  );
}
