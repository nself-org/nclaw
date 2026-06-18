/**
 * SubThreadScreen — a single conversation thread + its nested sub-threads.
 *
 * Purpose: Thread detail view (feature-spec §1a rows "Sub-thread" / thread nesting).
 *   Loads a conversation's messages via the chat GraphQL surface and renders them
 *   in an inverted FlatList (chat direction), plus a list of branched sub-threads
 *   (branchParentId chain) the user can drill into. Reached from the history list.
 *
 * Inputs:  Route param `id` (conversation UUID). Messages via THREAD_MESSAGES query.
 * Outputs: Inverted message list + sub-thread branch links + composer entry.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - RTL: bubbles + rows flip with useDirection().
 *   - Every Pressable has accessibilityLabel.
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: types/chat.ts (ChatMessage), app/(tabs)/chat.tsx (composer), history.tsx (entry).
 */

import React, { useCallback, useMemo } from 'react';
import { View, Text, FlatList, Pressable, type ListRenderItemInfo } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { gql, useQuery } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import type { ChatMessage } from '../../types/chat';

// ─── GraphQL: thread messages + branch children (documented contract) ─────────

/**
 * THREAD_MESSAGES — load all messages for a conversation plus its sub-thread
 * branches. Mirrors the Hasura `nclaw_messages` / `nclaw_conversations` schema
 * used by the chat surface (conversation_id FK, branch_parent_id self-FK).
 */
const THREAD_MESSAGES = gql`
  query ThreadMessages($conversationId: uuid!) {
    nclaw_messages(
      where: { conversation_id: { _eq: $conversationId } }
      order_by: { created_at: desc }
    ) {
      id
      role
      content
      created_at
    }
    nclaw_conversations(
      where: { branch_parent_id: { _eq: $conversationId } }
      order_by: { updated_at: desc }
    ) {
      id
      title
      message_count
    }
  }
`;

interface ThreadMessageRow {
  id: string;
  role: ChatMessage['role'];
  content: string;
  created_at: string;
}

interface BranchRow {
  id: string;
  title: string | null;
  message_count: number;
}

interface ThreadMessagesData {
  nclaw_messages: ThreadMessageRow[];
  nclaw_conversations: BranchRow[];
}

// ─── Message bubble ─────────────────────────────────────────────────────────

function Bubble({ message }: { message: ChatMessage }) {
  const { t } = useTranslation();
  const dir = useDirection();
  const isSent = message.role === 'user';
  const roleLabel = isSent ? t('chat.you', 'You') : t('chat.assistant', 'ɳClaw');

  return (
    <View
      className={`w-full px-3 py-1 ${isSent ? 'items-end' : 'items-start'}`}
      accessibilityRole="text"
      accessibilityLabel={`${roleLabel}: ${message.content}`}
    >
      <View
        className={`max-w-[80%] rounded-2xl px-4 py-3 ${isSent ? 'bg-primary' : 'bg-card'}`}
        style={{ flexDirection: dir.flexRow }}
      >
        <Text
          className={`text-base leading-relaxed ${isSent ? 'text-primary-foreground' : 'text-foreground'}`}
          style={{ textAlign: dir.textAlign }}
        >
          {message.content}
        </Text>
      </View>
    </View>
  );
}

// ─── SubThreadScreen ────────────────────────────────────────────────────────

export default function SubThreadScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const { id } = useLocalSearchParams<{ id: string }>();
  const conversationId = typeof id === 'string' ? id : '';

  const [result, refetch] = useQuery<ThreadMessagesData>({
    query: THREAD_MESSAGES,
    variables: { conversationId },
    pause: !conversationId,
  });

  const messages = useMemo<ChatMessage[]>(
    () =>
      (result.data?.nclaw_messages ?? []).map((m) => ({
        id: m.id,
        role: m.role,
        content: m.content,
        createdAt: m.created_at,
        threadId: conversationId,
      })),
    [result.data, conversationId],
  );

  const branches = result.data?.nclaw_conversations ?? [];

  // Map urql fetch state → AsyncScreen status.
  const status: ScreenStatus = result.fetching
    ? 'loading'
    : result.error
      ? 'error'
      : messages.length === 0
        ? 'empty'
        : 'data';

  const renderMessage = useCallback(
    ({ item }: ListRenderItemInfo<ChatMessage>) => <Bubble message={item} />,
    [],
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
          className="flex-1 text-lg font-semibold text-foreground"
          style={{ textAlign: dir.textAlign }}
          numberOfLines={1}
        >
          {t('thread.title', 'Conversation')}
        </Text>
      </View>

      {/* Sub-thread branches */}
      {branches.length > 0 && (
        <View className="px-4 py-2 border-b border-border">
          <Text className="text-xs font-semibold text-muted-foreground uppercase mb-2" style={{ textAlign: dir.textAlign }}>
            {t('thread.branches', 'Sub-threads')}
          </Text>
          {branches.map((b) => (
            <Pressable
              key={b.id}
              onPress={() => router.push(`/thread/${b.id}`)}
              className="flex-row items-center py-2"
              accessibilityLabel={`${b.title ?? t('thread.untitled', 'Untitled')} — ${b.message_count} ${t('history.messages', 'msgs')}`}
              accessibilityRole="button"
              style={{ flexDirection: dir.flexRow }}
            >
              <Text className="mr-2">🪢</Text>
              <Text className="flex-1 text-sm text-foreground" style={{ textAlign: dir.textAlign }} numberOfLines={1}>
                {b.title ?? t('thread.untitled', 'Untitled')}
              </Text>
              <Text className="text-xs text-muted-foreground">{b.message_count}</Text>
            </Pressable>
          ))}
        </View>
      )}

      {/* Messages */}
      <AsyncScreen
        status={status}
        error={result.error ?? null}
        onRetry={() => refetch({ requestPolicy: 'network-only' })}
        onReAuth={() => router.push('/auth/login')}
        testID="thread-detail"
        emptyMessage={t('thread.empty', 'No messages in this thread yet')}
      >
        <FlatList
          data={messages}
          renderItem={renderMessage}
          keyExtractor={(m) => m.id}
          inverted
          contentContainerStyle={{ paddingVertical: 8 }}
          showsVerticalScrollIndicator={false}
          accessibilityLabel={t('thread.listLabel', 'Thread messages')}
        />
      </AsyncScreen>

      {/* Continue in composer */}
      <Pressable
        onPress={() => router.push('/(tabs)/chat')}
        className="m-4 py-3 rounded-2xl items-center bg-primary"
        accessibilityLabel={t('thread.continue', 'Continue this conversation')}
        accessibilityRole="button"
      >
        <Text className="text-base font-semibold text-primary-foreground">
          {t('thread.continue', 'Continue conversation')}
        </Text>
      </Pressable>
    </View>
  );
}
