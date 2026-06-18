/**
 * UsageScreen — token + cost dashboard.
 *
 * Purpose: Token / cost usage dashboard (feature-spec §1a row "Usage"). Shows
 *   total tokens, total cost, and a per-day breakdown for the current period via
 *   the documented usage GraphQL contract. Distinct from API Usage (per-model).
 *
 * Inputs:  Usage rows via USAGE_SUMMARY query (Hasura nclaw_usage_daily view).
 * Outputs: Headline totals + per-day usage list.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: api-usage.tsx (per-model), Hasura nclaw_usage_daily.
 */

import React, { useMemo } from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { gql, useQuery } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

/**
 * USAGE_SUMMARY — daily token + cost totals for the current period.
 * Mirrors the Hasura `nclaw_usage_daily` aggregate view contract.
 */
const USAGE_SUMMARY = gql`
  query UsageSummary {
    nclaw_usage_daily(order_by: { day: desc }, limit: 30) {
      day
      total_tokens
      cost_usd
    }
  }
`;

interface UsageDayRow {
  day: string;
  total_tokens: number;
  cost_usd: number;
}

interface UsageSummaryData {
  nclaw_usage_daily: UsageDayRow[];
}

export default function UsageScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [result, refetch] = useQuery<UsageSummaryData>({ query: USAGE_SUMMARY });
  const rows = useMemo(() => result.data?.nclaw_usage_daily ?? [], [result.data]);

  const totals = useMemo(
    () =>
      rows.reduce(
        (acc, r) => ({ tokens: acc.tokens + r.total_tokens, cost: acc.cost + r.cost_usd }),
        { tokens: 0, cost: 0 },
      ),
    [rows],
  );

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
          {t('usage.title', 'Usage')}
        </Text>
        <Pressable
          onPress={() => router.push('/api-usage')}
          className="p-2"
          accessibilityLabel={t('usage.byModel', 'Usage by model')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>📊</Text>
        </Pressable>
      </View>

      <AsyncScreen
        status={status}
        error={result.error ?? null}
        onRetry={() => refetch({ requestPolicy: 'network-only' })}
        onReAuth={() => router.push('/auth/login')}
        testID="usage"
        emptyMessage={t('usage.empty', 'No usage recorded yet')}
      >
        {/* Headline totals */}
        <View className="flex-row gap-3 px-4 pt-4" style={{ flexDirection: dir.flexRow }}>
          <View className="flex-1 rounded-xl bg-card border border-border p-4">
            <Text className="text-xs text-muted-foreground" style={{ textAlign: dir.textAlign }}>
              {t('usage.totalTokens', 'Total tokens')}
            </Text>
            <Text className="text-2xl font-bold text-foreground mt-1">{totals.tokens.toLocaleString()}</Text>
          </View>
          <View className="flex-1 rounded-xl bg-card border border-border p-4">
            <Text className="text-xs text-muted-foreground" style={{ textAlign: dir.textAlign }}>
              {t('usage.totalCost', 'Total cost')}
            </Text>
            <Text className="text-2xl font-bold text-foreground mt-1">${totals.cost.toFixed(2)}</Text>
          </View>
        </View>

        {/* Per-day list */}
        <FlatList
          data={rows}
          keyExtractor={(r) => r.day}
          contentContainerStyle={{ padding: 16 }}
          renderItem={({ item }) => (
            <View
              className="flex-row items-center py-3 border-b border-border"
              style={{ flexDirection: dir.flexRow }}
              accessibilityLabel={`${item.day}: ${item.total_tokens} ${t('usage.tokens', 'tokens')}, $${item.cost_usd.toFixed(2)}`}
            >
              <Text className="flex-1 text-base text-foreground" style={{ textAlign: dir.textAlign }}>
                {new Date(item.day).toLocaleDateString()}
              </Text>
              <Text className="text-sm text-muted-foreground mr-4">
                {item.total_tokens.toLocaleString()} {t('usage.tokens', 'tok')}
              </Text>
              <Text className="text-sm font-medium text-foreground">${item.cost_usd.toFixed(2)}</Text>
            </View>
          )}
          showsVerticalScrollIndicator={false}
          accessibilityLabel={t('usage.listLabel', 'Daily usage')}
        />
      </AsyncScreen>
    </View>
  );
}
