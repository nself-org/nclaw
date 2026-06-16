/**
 * SearchScreen — cross-conversation search (UI only).
 *
 * Purpose: Full-text search across all conversation messages.
 *   Shows result list with message snippets and thread links.
 *   Backend search wired in T05. This ticket: UI only.
 *
 * Inputs:  Search query from TextInput; results from stub (wired in T05).
 * Outputs: Search input + results list.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *   - RTL: all layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T05 (memory search backend), useAutoTopics.
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  FlatList,
  Pressable,
  type ListRenderItemInfo,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';
import type { SearchResult } from '../types/chat';

// ─── Result row ───────────────────────────────────────────────────────────────

interface ResultRowProps {
  result: SearchResult;
  onPress: (threadId: string) => void;
}

function ResultRow({ result, onPress }: ResultRowProps) {
  const { t } = useTranslation();
  const dir = useDirection();
  const date = new Date(result.createdAt).toLocaleDateString();

  return (
    <Pressable
      onPress={() => onPress(result.threadId)}
      className="px-4 py-3 border-b border-border bg-background"
      accessibilityLabel={`${result.threadTitle}: ${result.snippet}`}
      accessibilityRole="button"
      style={{ flexDirection: dir.flexRow, alignItems: 'flex-start' }}
    >
      <View className="flex-1">
        <Text
          className="text-sm font-semibold text-primary mb-0.5"
          style={{ textAlign: dir.textAlign }}
          numberOfLines={1}
        >
          {result.threadTitle}
        </Text>
        <Text
          className="text-base text-foreground"
          style={{ textAlign: dir.textAlign }}
          numberOfLines={3}
        >
          {result.snippet}
        </Text>
        <Text className="text-xs text-muted-foreground mt-1">{date}</Text>
      </View>
      <Text
        className="text-muted-foreground text-xs"
        style={dir.marginStart(8)}
      >
        {dir.isRTL ? '‹' : '›'}
      </Text>
    </Pressable>
  );
}

// ─── SearchScreen ─────────────────────────────────────────────────────────────

export default function SearchScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [query, setQuery] = useState('');
  const [results] = useState<SearchResult[]>([]);
  const [status, setStatus] = useState<ScreenStatus>('data');
  const [hasSearched, setHasSearched] = useState(false);

  const handleSearch = useCallback((text: string) => {
    setQuery(text);
    if (text.trim().length >= 3) {
      setStatus('loading');
      setHasSearched(true);
      // Debounced search wired in T05
      // Stub: show empty after "loading"
      setTimeout(() => setStatus('data'), 400);
    } else {
      setHasSearched(false);
      setStatus('data');
    }
  }, []);

  const handleResultPress = useCallback(
    (threadId: string) => {
      router.push(`/thread/${threadId}`);
    },
    [router],
  );

  const renderResult = useCallback(
    ({ item }: ListRenderItemInfo<SearchResult>) => (
      <ResultRow result={item} onPress={handleResultPress} />
    ),
    [handleResultPress],
  );

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
          {t('search.title', 'Search')}
        </Text>
      </View>

      {/* Search input */}
      <View className="px-4 py-3 border-b border-border">
        <View
          className="flex-row items-center bg-muted rounded-xl px-3 py-2"
          style={{ flexDirection: dir.flexRow }}
        >
          <Text className="text-base mr-2">🔍</Text>
          <TextInput
            value={query}
            onChangeText={handleSearch}
            placeholder={t('search.placeholder', 'Search all conversations...')}
            placeholderTextColor="#888"
            className="flex-1 text-base text-foreground"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('search.inputLabel', 'Search conversations')}
            autoFocus
            returnKeyType="search"
            clearButtonMode="while-editing"
          />
        </View>
      </View>

      {/* Results */}
      <AsyncScreen
        status={status}
        testID="search-results"
        onRetry={() => handleSearch(query)}
        emptyMessage={
          hasSearched
            ? t('search.noResults', 'No results found')
            : t('search.empty', 'Type to search')
        }
      >
        {!hasSearched ? (
          <View className="flex-1 items-center justify-center px-8">
            <Text className="text-4xl mb-4">🔍</Text>
            <Text className="text-base text-muted-foreground text-center">
              {t('search.hint', 'Search across all your conversations and memories.')}
            </Text>
          </View>
        ) : results.length === 0 ? (
          <View className="flex-1 items-center justify-center px-8">
            <Text className="text-4xl mb-4">🤷</Text>
            <Text className="text-base text-muted-foreground text-center">
              {t('search.noResults', 'No results for')} "{query}"
            </Text>
          </View>
        ) : (
          <FlatList<SearchResult>
            data={results}
            renderItem={renderResult}
            keyExtractor={(item: SearchResult) => item.messageId}
            showsVerticalScrollIndicator={false}
            accessibilityLabel={t('search.resultsList', 'Search results')}
          />
        )}
      </AsyncScreen>
    </View>
  );
}
