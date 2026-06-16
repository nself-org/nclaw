/**
 * TopicsScreen — auto-topic sidebar / full-page topic list.
 *
 * Purpose: Displays all auto-detected and user-created topic tags. Allows
 *   manual topic creation. Tapping a topic filters the history list.
 *   Maps to feature-spec §2 Auto-Topics.
 *
 * Inputs:  Topic list from local state stub (wired to GraphQL in T04).
 * Outputs: List of topic nodes + manual creation form.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *   - RTL: all layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: useAutoTopics hook (auto-topic detection), T04 (backend wiring).
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  FlatList,
  TextInput,
  Pressable,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';
import type { TopicNode } from '../types/chat';

// ─── Stub data ─────────────────────────────────────────────────────────────────

const AUTO_TOPICS: TopicNode[] = [
  { id: 'code',     label: 'Code',     threadCount: 0, isManual: false },
  { id: 'planning', label: 'Planning', threadCount: 0, isManual: false },
  { id: 'personal', label: 'Personal', threadCount: 0, isManual: false },
  { id: 'research', label: 'Research', threadCount: 0, isManual: false },
  { id: 'task',     label: 'Tasks',    threadCount: 0, isManual: false },
];

// ─── Topic row ────────────────────────────────────────────────────────────────

interface TopicRowProps {
  topic: TopicNode;
  onPress: (id: string) => void;
}

function TopicRow({ topic, onPress }: TopicRowProps) {
  const { t } = useTranslation();
  const dir = useDirection();

  return (
    <Pressable
      onPress={() => onPress(topic.id)}
      className="flex-row items-center px-4 py-3 bg-background border-b border-border"
      accessibilityLabel={`${topic.label} — ${topic.threadCount} ${t('topics.threads', 'threads')}`}
      accessibilityRole="button"
      style={{ flexDirection: dir.flexRow }}
    >
      {/* Tag pill */}
      <View className="px-2 py-0.5 rounded-full bg-primary/10 mr-3">
        <Text className="text-xs text-primary font-medium">
          {topic.id}
        </Text>
      </View>

      <Text
        className="flex-1 text-base text-foreground"
        style={{ textAlign: dir.textAlign }}
      >
        {topic.label}
      </Text>

      <Text className="text-sm text-muted-foreground">
        {topic.threadCount}
        {topic.isManual && (
          <Text className="text-xs text-muted-foreground ml-1">
            {' '}({t('topics.manual', 'manual')})
          </Text>
        )}
      </Text>
    </Pressable>
  );
}

// ─── TopicsScreen ─────────────────────────────────────────────────────────────

export default function TopicsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status] = useState<ScreenStatus>('data');
  const [topics, setTopics] = useState<TopicNode[]>(AUTO_TOPICS);
  const [newTopicName, setNewTopicName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  const handleTopicPress = useCallback(
    (topicId: string) => {
      router.push({ pathname: '/(tabs)/history', params: { topicId } });
    },
    [router],
  );

  const handleCreateTopic = useCallback(() => {
    const name = newTopicName.trim();
    if (!name) return;

    const newTopic: TopicNode = {
      id: `manual-${Date.now()}`,
      label: name,
      threadCount: 0,
      isManual: true,
    };
    setTopics((prev) => [...prev, newTopic]);
    setNewTopicName('');
    setIsCreating(false);
    // Backend mutation wired in T04
  }, [newTopicName]);

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
          {t('topics.title', 'Topics')}
        </Text>
        <Pressable
          onPress={() => setIsCreating(true)}
          className="p-2"
          accessibilityLabel={t('topics.createNew', 'Create new topic')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>+</Text>
        </Pressable>
      </View>

      {/* Manual topic creation form */}
      {isCreating && (
        <View className="px-4 py-3 bg-muted border-b border-border">
          <Text className="text-sm font-medium text-foreground mb-2" style={{ textAlign: dir.textAlign }}>
            {t('topics.newTopicLabel', 'New topic name')}
          </Text>
          <View
            className="flex-row items-center gap-2"
            style={{ flexDirection: dir.flexRow }}
          >
            <TextInput
              value={newTopicName}
              onChangeText={setNewTopicName}
              placeholder={t('topics.newTopicPlaceholder', 'e.g. family, fitness...')}
              placeholderTextColor="#888"
              className="flex-1 bg-background rounded-xl px-4 py-2 text-base text-foreground border border-border"
              style={{ textAlign: dir.textAlign }}
              accessibilityLabel={t('topics.newTopicLabel', 'New topic name')}
              autoFocus
              returnKeyType="done"
              onSubmitEditing={handleCreateTopic}
            />
            <Pressable
              onPress={handleCreateTopic}
              className="px-4 py-2 bg-primary rounded-xl"
              accessibilityLabel={t('topics.create', 'Create')}
              accessibilityRole="button"
            >
              <Text className="text-primary-foreground font-medium">
                {t('topics.create', 'Create')}
              </Text>
            </Pressable>
            <Pressable
              onPress={() => { setIsCreating(false); setNewTopicName(''); }}
              className="px-3 py-2"
              accessibilityLabel={t('common.cancel', 'Cancel')}
              accessibilityRole="button"
            >
              <Text className="text-muted-foreground">
                {t('common.cancel', 'Cancel')}
              </Text>
            </Pressable>
          </View>
        </View>
      )}

      {/* Topic list */}
      <AsyncScreen
        status={status}
        testID="topics"
        emptyMessage={t('topics.empty', 'No topics yet')}
      >
        <FlatList
          data={topics}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <TopicRow topic={item} onPress={handleTopicPress} />
          )}
          showsVerticalScrollIndicator={false}
          accessibilityLabel={t('topics.listLabel', 'Topic list')}
          ListFooterComponent={
            <Text className="text-xs text-muted-foreground text-center py-4 px-4">
              {t('topics.autoNote', 'Topics are automatically assigned by ɳClaw based on conversation content.')}
            </Text>
          }
        />
      </AsyncScreen>
    </View>
  );
}
