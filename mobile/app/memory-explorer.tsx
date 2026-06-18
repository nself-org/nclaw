/**
 * MemoryExplorerScreen — pgvector semantic memory search + type facets.
 *
 * Purpose: Full memory explorer (feature-spec §3). Runs semantic search over
 *   persistent memories via the libnclaw JSI seam (getNcLawJSI().memorySearch),
 *   renders results grouped/filterable by MemoryType facet, and shows a
 *   "memory health" summary (count + confidence). Replaces the memory tab stub's
 *   forward link.
 *
 * Inputs:  Search query (debounced), MemoryType facet selection.
 *          Memory data from NcLawJSI.memorySearch (pgvector cosine search).
 * Outputs: Facet chip row + ranked memory result list with confidence + type badge.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen (loading / empty / error / data / offline /
 *     permission-denied / rate-limited).
 *   - All text via t() with inline defaults.
 *   - Every Pressable / TextInput has accessibilityLabel.
 *   - RTL: layouts flip with useDirection().
 *   - Never blocks the JS thread — memorySearch dispatched via JSI promise.
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: useMemoryRecall (same JSI seam), feature-preservation-inventory §1a row "Memory explorer".
 */

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, FlatList } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { getNcLawJSI, type Memory, type MemoryType } from '@nself/native-bridge';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

/** Max memory results to retrieve per semantic search. */
const SEARCH_LIMIT = 25;
/** Debounce delay (ms) before dispatching a semantic search. */
const DEBOUNCE_MS = 350;

/** All MemoryType facets plus an "all" pseudo-facet. */
const FACETS: { key: MemoryType | 'all'; emoji: string }[] = [
  { key: 'all', emoji: '🧠' },
  { key: 'fact', emoji: '📌' },
  { key: 'preference', emoji: '⭐' },
  { key: 'goal', emoji: '🎯' },
  { key: 'event', emoji: '📅' },
  { key: 'relationship', emoji: '🔗' },
  { key: 'rule', emoji: '📏' },
];

// ─── Memory row ─────────────────────────────────────────────────────────────

function MemoryRow({ memory }: { memory: Memory }) {
  const { t } = useTranslation();
  const dir = useDirection();
  const confidencePct = Math.round(memory.confidence * 100);

  return (
    <View
      className="px-4 py-3 bg-background border-b border-border"
      accessibilityLabel={`${t(`memoryExplorer.type.${memory.memoryType}`, memory.memoryType)}: ${memory.content}. ${confidencePct}% ${t('memoryExplorer.confidence', 'confidence')}`}
    >
      <View
        className="flex-row items-center mb-1"
        style={{ flexDirection: dir.flexRow }}
      >
        <View className="px-2 py-0.5 rounded-full bg-primary/10 mr-2">
          <Text className="text-xs text-primary font-medium">
            {t(`memoryExplorer.type.${memory.memoryType}`, memory.memoryType)}
          </Text>
        </View>
        <Text className="text-xs text-muted-foreground">
          {confidencePct}%
        </Text>
      </View>
      <Text
        className="text-base text-foreground"
        style={{ textAlign: dir.textAlign }}
      >
        {memory.content}
      </Text>
    </View>
  );
}

// ─── MemoryExplorerScreen ───────────────────────────────────────────────────

export default function MemoryExplorerScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('empty');
  const [query, setQuery] = useState('');
  const [facet, setFacet] = useState<MemoryType | 'all'>('all');
  const [results, setResults] = useState<Memory[]>([]);
  const [error, setError] = useState<Error | null>(null);

  // Debounced semantic search via the libnclaw JSI seam (pgvector cosine).
  const runSearch = useCallback(async (q: string) => {
    if (!q.trim()) {
      setResults([]);
      setStatus('empty');
      return;
    }
    setStatus('loading');
    setError(null);
    try {
      const memories = await getNcLawJSI().memorySearch(q.trim(), SEARCH_LIMIT);
      setResults(memories);
      setStatus(memories.length === 0 ? 'empty' : 'data');
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus('error');
    }
  }, []);

  useEffect(() => {
    const handle = setTimeout(() => {
      void runSearch(query);
    }, DEBOUNCE_MS);
    return () => clearTimeout(handle);
  }, [query, runSearch]);

  // Apply the active facet filter client-side (search is type-agnostic).
  const filtered = useMemo(
    () =>
      facet === 'all'
        ? results
        : results.filter((m) => m.memoryType === facet),
    [results, facet],
  );

  const avgConfidence = useMemo(() => {
    if (filtered.length === 0) return 0;
    const sum = filtered.reduce((acc, m) => acc + m.confidence, 0);
    return Math.round((sum / filtered.length) * 100);
  }, [filtered]);

  return (
    <View className="flex-1 bg-background">
      {/* Header */}
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
        <Text
          className="flex-1 text-xl font-bold text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {t('memoryExplorer.title', 'Memory Explorer')}
        </Text>
      </View>

      {/* Search bar */}
      <View className="px-4 py-2 border-b border-border">
        <View
          className="flex-row items-center bg-muted rounded-xl px-3 py-2"
          style={{ flexDirection: dir.flexRow }}
        >
          <Text className="text-base mr-2">🔍</Text>
          <TextInput
            value={query}
            onChangeText={setQuery}
            placeholder={t('memoryExplorer.searchPlaceholder', 'Semantic search across all memories...')}
            placeholderTextColor="#888"
            className="flex-1 text-base text-foreground"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('memoryExplorer.searchLabel', 'Search memories semantically')}
            returnKeyType="search"
            clearButtonMode="while-editing"
            autoFocus
          />
        </View>
      </View>

      {/* Facet chips */}
      <View className="border-b border-border">
        <FlatList
          horizontal
          data={FACETS}
          keyExtractor={(f) => f.key}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={{ paddingHorizontal: 12, paddingVertical: 8, gap: 8 }}
          renderItem={({ item }) => {
            const active = facet === item.key;
            return (
              <Pressable
                onPress={() => setFacet(item.key)}
                className={`px-3 py-1.5 rounded-full ${active ? 'bg-primary' : 'bg-muted'}`}
                accessibilityLabel={t(`memoryExplorer.facet.${item.key}`, item.key)}
                accessibilityRole="button"
                accessibilityState={{ selected: active }}
              >
                <Text
                  className={`text-sm ${active ? 'text-primary-foreground font-medium' : 'text-muted-foreground'}`}
                >
                  {item.emoji} {t(`memoryExplorer.facet.${item.key}`, item.key)}
                </Text>
              </Pressable>
            );
          }}
        />
      </View>

      {/* Memory health summary */}
      {filtered.length > 0 && (
        <View
          className="px-4 py-2 bg-muted/50"
          accessibilityLabel={t('memoryExplorer.health', 'Memory health')}
        >
          <Text className="text-xs text-muted-foreground" style={{ textAlign: dir.textAlign }}>
            {t('memoryExplorer.healthSummary', '{{count}} memories · {{conf}}% avg confidence', {
              count: filtered.length,
              conf: avgConfidence,
            })}
          </Text>
        </View>
      )}

      {/* Results */}
      <AsyncScreen
        status={status}
        error={error}
        onRetry={() => runSearch(query)}
        onReAuth={() => router.push('/auth/login')}
        testID="memory-explorer"
        emptyMessage={
          query.trim()
            ? t('memoryExplorer.noResults', 'No matching memories')
            : t('memoryExplorer.startHint', 'Search to explore what ɳClaw remembers')
        }
      >
        <FlatList
          data={filtered}
          keyExtractor={(m) => m.id}
          renderItem={({ item }) => <MemoryRow memory={item} />}
          showsVerticalScrollIndicator={false}
          accessibilityLabel={t('memoryExplorer.listLabel', 'Memory results')}
        />
      </AsyncScreen>
    </View>
  );
}
