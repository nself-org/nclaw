/**
 * ChatScreen — AI chat composer + streaming response (T04: backend wiring complete).
 *
 * Purpose: Main chat interface. Renders a FlatList of messages (inverted for chat
 *   direction) with sent/received bubble variants, text input bar, and action buttons.
 *   AI send/receive/streaming wired in T04 via useSendMessage + useMessageStream.
 *
 * Inputs:  Messages from local state; useSendMessage for AI send; useMessageStream
 *          for GraphQL subscription streaming tokens.
 * Outputs: Scrollable message list + input bar with live streaming and error states.
 *
 * Constraints:
 *   - FlatList must use inverted=true (bottom-up chat direction).
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states must be handled via AsyncScreen.
 *   - All text via t() — zero hardcoded strings.
 *   - Every interactive element has accessibilityLabel.
 *   - RTL: input bar and bubbles flip with useDirection().
 *   - No send logic in JSX — useSendMessage owns all orchestration.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T04 (this ticket), T07 (voice input), T08 (file attachment).
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  FlatList,
  TextInput,
  Pressable,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  type ListRenderItemInfo,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useSubscription } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import { useSendMessage } from '../../hooks/useSendMessage';
import type { ChatMessage, ChatError } from '../../types/chat';
import {
  CHAT_MESSAGE_STREAM,
  type ChatMessageStreamData,
  type ChatMessageStreamVariables,
} from '../../services/chat';

// ─── Message Bubble ────────────────────────────────────────────────────────────

interface MessageBubbleProps {
  message: ChatMessage;
}

/**
 * MessageBubble — renders a single chat message as a sent or received bubble.
 * Sent (user): aligned to the "end" of the row (right in LTR, left in RTL).
 * Received (assistant): aligned to the "start".
 */
function MessageBubble({ message }: MessageBubbleProps) {
  const { t } = useTranslation();
  const dir = useDirection();
  const isSent = message.role === 'user';

  const containerAlign = isSent ? 'items-end' : 'items-start';
  const bubbleColor = isSent ? 'bg-primary' : 'bg-card';
  const textColor = isSent ? 'text-primary-foreground' : 'text-foreground';
  const roleLabel = isSent
    ? t('chat.you', 'You')
    : t('chat.assistant', 'ɳClaw');

  return (
    <View
      className={`w-full px-3 py-1 ${containerAlign}`}
      accessibilityRole="text"
      accessibilityLabel={`${roleLabel}: ${message.content}`}
    >
      <View
        className={`max-w-[80%] rounded-2xl px-4 py-3 ${bubbleColor}`}
        style={{ flexDirection: dir.flexRow }}
      >
        <Text
          className={`text-base leading-relaxed ${textColor}`}
          style={{ textAlign: dir.textAlign }}
        >
          {message.isStreaming ? `${message.content}▌` : message.content}
        </Text>
      </View>
      {message.attachment && (
        <View
          className="mt-1 flex-row items-center bg-muted rounded-xl px-3 py-2 max-w-[80%]"
          accessibilityLabel={`${t('chat.attachment', 'Attachment')}: ${message.attachment.name}`}
        >
          <Text className="text-xs text-muted-foreground" numberOfLines={1}>
            📎 {message.attachment.name}
          </Text>
        </View>
      )}
    </View>
  );
}

// ─── Empty chat placeholder ───────────────────────────────────────────────────

function EmptyChatPlaceholder() {
  const { t } = useTranslation();
  return (
    <View className="flex-1 items-center justify-center px-8">
      <Text className="text-5xl mb-4">💬</Text>
      <Text className="text-xl font-semibold text-foreground text-center">
        {t('chat.emptyHeading', 'Start a conversation')}
      </Text>
      <Text className="text-sm text-muted-foreground text-center mt-2">
        {t('chat.emptyHint', 'Type a message or tap the mic to speak.')}
      </Text>
    </View>
  );
}

// ─── Input Bar ─────────────────────────────────────────────────────────────────

interface InputBarProps {
  value: string;
  onChangeText: (text: string) => void;
  onSend: () => void;
  onVoice: () => void;
  onAttach: () => void;
  disabled?: boolean;
}

function InputBar({
  value,
  onChangeText,
  onSend,
  onVoice,
  onAttach,
  disabled,
}: InputBarProps) {
  const { t } = useTranslation();
  const dir = useDirection();
  const canSend = value.trim().length > 0 && !disabled;

  return (
    <View
      className="border-t border-border bg-background px-3 py-2"
      style={{ flexDirection: dir.flexRow, alignItems: 'flex-end' }}
    >
      {/* Attach button */}
      <Pressable
        onPress={onAttach}
        disabled={disabled}
        className="w-10 h-10 rounded-full items-center justify-center mr-2"
        accessibilityLabel={t('chat.attach', 'Attach file')}
        accessibilityRole="button"
        accessibilityState={{ disabled: !!disabled }}
      >
        <Text style={{ fontSize: 20 }}>📎</Text>
      </Pressable>

      {/* Text input */}
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={t('chat.placeholder', 'Message ɳClaw...')}
        placeholderTextColor="#888"
        multiline
        editable={!disabled}
        className="flex-1 bg-muted rounded-2xl px-4 py-2 text-base text-foreground max-h-28"
        style={{ textAlign: dir.textAlign }}
        accessibilityLabel={t('chat.inputLabel', 'Message input')}
        returnKeyType="send"
        onSubmitEditing={canSend ? onSend : undefined}
        blurOnSubmit={false}
      />

      {/* Voice button */}
      <Pressable
        onPress={onVoice}
        disabled={disabled}
        className="w-10 h-10 rounded-full items-center justify-center ml-2"
        accessibilityLabel={t('chat.voice', 'Voice input')}
        accessibilityRole="button"
        accessibilityState={{ disabled: !!disabled }}
      >
        <Text style={{ fontSize: 20 }}>🎙️</Text>
      </Pressable>

      {/* Send button */}
      <Pressable
        onPress={onSend}
        disabled={!canSend}
        className={`w-10 h-10 rounded-full items-center justify-center ml-2 ${
          canSend ? 'bg-primary' : 'bg-muted'
        }`}
        accessibilityLabel={t('chat.send', 'Send message')}
        accessibilityRole="button"
        accessibilityState={{ disabled: !canSend }}
      >
        <Text
          style={{ fontSize: 16 }}
          className={canSend ? 'text-primary-foreground' : 'text-muted-foreground'}
        >
          ↑
        </Text>
      </Pressable>
    </View>
  );
}

// ─── Error banner ─────────────────────────────────────────────────────────────

interface ErrorBannerProps {
  error: ChatError;
  onRetry: () => void;
}

/**
 * ErrorBanner — shown below the message list when a send fails.
 * Displays a user-visible message and a retry button.
 */
function ErrorBanner({ error, onRetry }: ErrorBannerProps) {
  const { t } = useTranslation();
  const isRetryable = error.kind === 'NetworkError' || error.kind === 'InferenceError';

  return (
    <View
      className="mx-3 mb-2 p-3 bg-destructive/10 rounded-xl flex-row items-center"
      accessibilityRole="alert"
    >
      <Text className="flex-1 text-sm text-destructive" numberOfLines={2}>
        {error.message}
      </Text>
      {isRetryable && (
        <Pressable
          onPress={onRetry}
          className="ml-3 px-3 py-1.5 bg-destructive rounded-lg"
          accessibilityLabel={t('chat.retry', 'Retry sending')}
          accessibilityRole="button"
        >
          <Text className="text-xs text-destructive-foreground font-medium">
            {t('chat.retry', 'Retry')}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

// ─── Typing indicator ─────────────────────────────────────────────────────────

/**
 * TypingIndicator — animated dots shown while inference is in-progress.
 * Appears as an assistant message bubble with a pulsing indicator.
 */
function TypingIndicator() {
  const { t } = useTranslation();
  return (
    <View
      className="w-full px-3 py-1 items-start"
      accessibilityLabel={t('chat.typingIndicator', 'ɳClaw is thinking')}
      accessible
    >
      <View className="bg-card rounded-2xl px-4 py-3 flex-row items-center gap-1">
        <ActivityIndicator size="small" color="#6C3CE1" />
        <Text className="text-xs text-muted-foreground ml-2">
          {t('chat.thinking', 'Thinking…')}
        </Text>
      </View>
    </View>
  );
}

// ─── ChatScreen ─────────────────────────────────────────────────────────────────

export default function ChatScreen() {
  const { t } = useTranslation();
  const router = useRouter();

  const [screenStatus] = useState<ScreenStatus>('data');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputText, setInputText] = useState('');
  const [conversationId, setConversationId] = useState<string | null>(null);
  // Sequence counter for streaming subscription cursor
  const streamSequenceRef = useRef(0);

  // ─── useSendMessage: wire all send orchestration ─────────────────────────
  const { sendMessage, isSending, isRecalling, error, retryLast } = useSendMessage({
    conversationId,
    onNewConversation: setConversationId,
    onOptimisticMessage: (msg) =>
      setMessages((prev: ChatMessage[]) => [msg, ...prev]),
    onMessageStatusChange: (id, status) =>
      setMessages((prev: ChatMessage[]) =>
        prev.map((m: ChatMessage) => (m.id === id ? { ...m, status } : m)),
      ),
  });

  // ─── useMessageStream: GraphQL subscription for streaming tokens ──────────
  const [streamResult] = useSubscription<
    ChatMessageStreamData,
    ChatMessageStreamData,
    ChatMessageStreamVariables
  >({
    query: CHAT_MESSAGE_STREAM,
    variables: {
      conversationId: conversationId ?? '',
      afterSequence: streamSequenceRef.current,
    },
    pause: !conversationId || !isSending,
  });

  // Process streaming token events and update the assistant message bubble
  useEffect(() => {
    const tokenRows = streamResult.data?.nclaw_message_tokens_stream;
    if (!tokenRows || tokenRows.length === 0) return;

    for (const row of tokenRows) {
      const { message_id, token_chunk, sequence, is_final } = row;

      setMessages((prev: ChatMessage[]) => {
        const existing = prev.find((m: ChatMessage) => m.id === message_id);
        if (!existing) {
          // First token: insert the streaming assistant bubble
          const assistantMsg: ChatMessage = {
            id: message_id,
            role: 'assistant',
            content: token_chunk,
            createdAt: new Date().toISOString(),
            threadId: conversationId ?? '',
            isStreaming: !is_final,
            status: null,
          };
          return [assistantMsg, ...prev];
        }
        // Subsequent tokens: append to the existing bubble
        return prev.map((m: ChatMessage) =>
          m.id === message_id
            ? { ...m, content: m.content + token_chunk, isStreaming: !is_final }
            : m,
        );
      });

      // Advance cursor so we don't re-receive tokens on re-subscribe
      streamSequenceRef.current = Math.max(streamSequenceRef.current, sequence + 1);
    }
  }, [streamResult.data, conversationId]);

  // ─── Handlers ────────────────────────────────────────────────────────────

  const handleSend = useCallback(async () => {
    const text = inputText.trim();
    if (!text || isSending) return;
    setInputText('');
    await sendMessage(text);
  }, [inputText, isSending, sendMessage]);

  const handleVoice = useCallback(() => {
    // Voice input wired in T07
    router.push('/voice-input');
  }, [router]);

  const handleAttach = useCallback(() => {
    // File picker wired in T08
    router.push('/attachment-picker');
  }, [router]);

  const renderMessage = useCallback(
    ({ item }: ListRenderItemInfo<ChatMessage>) => (
      <MessageBubble message={item} />
    ),
    [],
  );

  const keyExtractor = useCallback((item: ChatMessage) => item.id, []);

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-background"
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 88 : 0}
    >
      {/* Header */}
      <View className="flex-row items-center px-4 py-3 border-b border-border">
        <Text className="flex-1 text-lg font-semibold text-foreground">
          {t('chat.title', 'ɳClaw')}
        </Text>
        <Pressable
          onPress={() => router.push('/history')}
          className="p-2"
          accessibilityLabel={t('chat.openHistory', 'Open conversation history')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>📋</Text>
        </Pressable>
        <Pressable
          onPress={() => router.push('/settings')}
          className="p-2"
          accessibilityLabel={t('chat.openSettings', 'Open settings')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>⚙️</Text>
        </Pressable>
      </View>

      {/* Message list */}
      <AsyncScreen
        status={screenStatus}
        testID="chat-messages"
        emptyMessage={t('chat.emptyHeading', 'Start a conversation')}
      >
        {messages.length === 0 && !isSending ? (
          <EmptyChatPlaceholder />
        ) : (
          <FlatList
            data={messages}
            renderItem={renderMessage}
            keyExtractor={keyExtractor}
            inverted
            contentContainerStyle={{ paddingVertical: 8 }}
            showsVerticalScrollIndicator={false}
            accessibilityLabel={t('chat.messageList', 'Message list')}
            ListHeaderComponent={
              isSending && !isRecalling ? <TypingIndicator /> : null
            }
          />
        )}
      </AsyncScreen>

      {/* Error banner */}
      {error && <ErrorBanner error={error} onRetry={retryLast} />}

      {/* Recalling memory indicator */}
      {isRecalling && (
        <View className="px-4 py-1 flex-row items-center gap-2">
          <ActivityIndicator size="small" color="#6C3CE1" />
          <Text className="text-xs text-muted-foreground">
            {t('chat.recallingMemory', 'Recalling memory…')}
          </Text>
        </View>
      )}

      {/* Input bar */}
      <InputBar
        value={inputText}
        onChangeText={setInputText}
        onSend={handleSend}
        onVoice={handleVoice}
        onAttach={handleAttach}
        disabled={isSending}
      />
    </KeyboardAvoidingView>
  );
}
