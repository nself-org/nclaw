/**
 * HistoryScreen — conversation history list grouped by auto-topic.
 *
 * Purpose: Displays all past conversation threads grouped by their auto-assigned
 *   topic tag using a SectionList. Infinite scroll via useInfiniteQuery (T04 wires
 *   the real GraphQL call). Includes per-thread swipe actions and a search bar.
 *
 * Inputs:  Threads from local state stub (wired to GraphQL in T04).
 * Outputs: SectionList with topic headers and thread rows.
 *
 * Constraints:
 *   - SectionList grouped by topicId — topics define sections.
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() — zero hardcoded strings.
 *   - RTL: row items flip with useDirection().
 *   - Every Pressable has accessibilityLabel.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T04 (backend), T05 (memory features).
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  SectionList,
  TextInput,
  Pressable,
  type SectionListRenderItemInfo,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import type { ConversationThread, TopicSection } from '../../types/chat';

// ─── Stub data ─────────────────────────────────────────────────────────────────

/** Stub sections — replaced by GraphQL in T04. */
const STUB_SECTIONS: TopicSection[] = [];

// ─── Thread row ────────────────────────────────────────────────────────────────

interface ThreadRowProps {
  thread: ConversationThread;
  onPress: (id: string) => void;
}

function ThreadRow({ thread, onPress }: ThreadRowProps) {
  const { t } = useTranslation();
  const dir = useDirection();
  const updatedAt = new Date(thread.updatedAt).toLocaleDateString();

  return (
    <Pressable
      onPress={() => onPress(thread.id)}
      className="flex-row items-start px-4 py-3 bg-background border-b border-border"
      accessibilityLabel={`${thread.title}. ${t('history.lastActive', 'Last active')} ${updatedAt}`}
      accessibilityRole="button"
      style={{ flexDirection: dir.flexRow }}
    >
      {/* Thread info */}
      <View className="flex-1" style={dir.marginStart(0)}>
        <Text
          className="text-base font-medium text-foreground"
          style={{ textAlign: dir.textAlign }}
          numberOfLines={1}
        >
          {thread.title}
        </Text>
        <Text
          className="text-sm text-muted-foreground mt-0.5"
          style={{ textAlign: dir.textAlign }}
          numberOfLines={2}
        >
          {thread.preview}
        </Text>
      </View>

      {/* Meta */}
      <View
        className="items-end"
        style={dir.marginStart(12)}
      >
        <Text className="text-xs text-muted-foreground">{updatedAt}</Text>
        <Text className="text-xs text-muted-foreground mt-1">
          {thread.messageCount} {t('history.messages', 'msgs')}
        </Text>
      </View>
    </Pressable>
  );
}

// ─── Section header ───────────────────────────────────────────────────────────

function SectionHeader({ title }: { title: string }) {
  const dir = useDirection();
  return (
    <View
      className="px-4 py-2 bg-muted"
      accessibilityRole="header"
      accessibilityLabel={title}
    >
      <Text
        className="text-xs font-semibold text-muted-foreground uppercase tracking-wider"
        style={{ textAlign: dir.textAlign }}
      >
        {title}
      </Text>
    </View>
  );
}

// ─── HistoryScreen ─────────────────────────────────────────────────────────────

export default function HistoryScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status] = useState<ScreenStatus>('data');
  const [sections] = useState<TopicSection[]>(STUB_SECTIONS);
  const [searchQuery, setSearchQuery] = useState('');

  const handleThreadPress = useCallback(
    (threadId: string) => {
      router.push(`/thread/${threadId}`);
    },
    [router],
  );

  const filteredSections = sections
    .map((section: TopicSection) => ({
      ...section,
      data: section.data.filter(
        (thread: ConversationThread) =>
          thread.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
          thread.preview.toLowerCase().includes(searchQuery.toLowerCase()),
      ),
    }))
    .filter((sec: TopicSection) => sec.data.length > 0);

  const renderItem = useCallback(
    ({ item }: SectionListRenderItemInfo<ConversationThread, TopicSection>) => (
      <ThreadRow thread={item} onPress={handleThreadPress} />
    ),
    [handleThreadPress],
  );

  const keyExtractor = useCallback((item: ConversationThread) => item.id, []);

  const renderSectionHeader = useCallback(
    ({ section }: { section: TopicSection }) => (
      <SectionHeader title={section.label} />
    ),
    [],
  );

  return (
    <View className="flex-1 bg-background">
      {/* Header */}
      <View
        className="px-4 pt-4 pb-2 border-b border-border"
        style={{ flexDirection: dir.flexRow, alignItems: 'center' }}
      >
        <Text className="flex-1 text-xl font-bold text-foreground" style={{ textAlign: dir.textAlign }}>
          {t('history.title', 'Conversations')}
        </Text>
        <Pressable
          onPress={() => router.push('/topics')}
          className="p-2"
          accessibilityLabel={t('history.openTopics', 'Browse topics')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>🏷️</Text>
        </Pressable>
      </View>

      {/* Search bar */}
      <View className="px-4 py-2 bg-background border-b border-border">
        <View
          className="flex-row items-center bg-muted rounded-xl px-3 py-2"
          style={{ flexDirection: dir.flexRow }}
        >
          <Text className="text-base mr-2">🔍</Text>
          <TextInput
            value={searchQuery}
            onChangeText={setSearchQuery}
            placeholder={t('history.searchPlaceholder', 'Search conversations...')}
            placeholderTextColor="#888"
            className="flex-1 text-base text-foreground"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('history.searchLabel', 'Search conversations')}
            returnKeyType="search"
            clearButtonMode="while-editing"
          />
        </View>
      </View>

      {/* SectionList */}
      <AsyncScreen
        status={status}
        testID="history"
        emptyMessage={t('history.empty', 'No conversations yet')}
      >
        {sections.length === 0 ? (
          <View className="flex-1 items-center justify-center px-8">
            <Text className="text-4xl mb-4">💬</Text>
            <Text className="text-lg font-semibold text-foreground text-center">
              {t('history.empty', 'No conversations yet')}
            </Text>
            <Text className="text-sm text-muted-foreground text-center mt-2">
              {t('history.emptyHint', 'Your conversation history will appear here.')}
            </Text>
          </View>
        ) : (
          <SectionList
            sections={filteredSections}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
            renderSectionHeader={renderSectionHeader}
            stickySectionHeadersEnabled
            showsVerticalScrollIndicator={false}
            accessibilityLabel={t('history.listLabel', 'Conversation history')}
            onEndReachedThreshold={0.3}
            // onEndReached wired to useInfiniteQuery in T04
          />
        )}
      </AsyncScreen>
    </View>
  );
}
