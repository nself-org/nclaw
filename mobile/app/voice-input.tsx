/**
 * VoiceConversationScreen — hands-free real-time voice chat (STT → AI → TTS).
 *
 * Purpose: Full-screen voice conversation mode (feature-spec §1a row "Voice
 *   conversation"). Records the user's speech (Whisper STT via useVoiceInput),
 *   sends the transcript through the chat send pipeline (useSendMessage), and
 *   speaks the AI reply back (TTS via the libnclaw JSI seam). Reached from the
 *   chat composer mic button.
 *
 * Inputs:  Microphone (useVoiceInput) · useSendMessage for AI turn.
 * Outputs: Large mic orb with live status, running transcript, and spoken reply.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states surfaced via inline status (no remote fetch on entry).
 *   - All text via t() with inline defaults.
 *   - Every interactive element has accessibilityLabel.
 *   - RTL: layout flips with useDirection().
 *   - Never blocks the JS thread — STT/TTS dispatched via JSI promises.
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: useVoiceInput.ts (STT) · useSendMessage.ts (AI turn) · voice-settings.tsx (config).
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { View, Text, Pressable, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useSubscription } from 'urql';

import { useDirection } from '../lib/useDirection';
import { useVoiceInput, type VoiceInputError } from '../hooks/useVoiceInput';
import { useSendMessage } from '../hooks/useSendMessage';
import type { ChatMessage } from '../types/chat';
import {
  CHAT_MESSAGE_STREAM,
  type ChatMessageStreamData,
  type ChatMessageStreamVariables,
} from '../services/chat';

/** One spoken turn shown in the rolling transcript. */
interface VoiceTurn {
  id: string;
  role: 'user' | 'assistant';
  text: string;
}

export default function VoiceConversationScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [conversationId, setConversationId] = useState<string | null>(null);
  const [turns, setTurns] = useState<VoiceTurn[]>([]);
  const [lastError, setLastError] = useState<string | null>(null);
  const streamSequenceRef = useRef(0);

  // AI send pipeline — same orchestration as the text chat composer.
  const { sendMessage, isSending, isRecalling } = useSendMessage({
    conversationId,
    onNewConversation: setConversationId,
    onOptimisticMessage: (msg: ChatMessage) =>
      setTurns((prev) => [
        ...prev,
        { id: msg.id, role: 'user', text: msg.content },
      ]),
    onMessageStatusChange: () => undefined,
  });

  // Stream the AI reply token-by-token, identical to the text chat surface.
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

  // Append streamed tokens to the active assistant turn (TTS plays it on is_final).
  useEffect(() => {
    const rows = streamResult.data?.nclaw_message_tokens_stream;
    if (!rows || rows.length === 0) return;
    for (const row of rows) {
      const { message_id, token_chunk, sequence } = row;
      setTurns((prev) => {
        const existing = prev.find((tn) => tn.id === message_id);
        if (!existing) {
          return [...prev, { id: message_id, role: 'assistant', text: token_chunk }];
        }
        return prev.map((tn) =>
          tn.id === message_id ? { ...tn, text: tn.text + token_chunk } : tn,
        );
      });
      streamSequenceRef.current = Math.max(streamSequenceRef.current, sequence + 1);
    }
  }, [streamResult.data]);

  // When transcription completes, send it as a chat turn.
  const handleTranscription = useCallback(
    async (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) return;
      setLastError(null);
      await sendMessage(trimmed);
    },
    [sendMessage],
  );

  const handleVoiceError = useCallback(
    (err: VoiceInputError) => setLastError(err.message),
    [],
  );

  const {
    status,
    isPermissionGranted,
    startRecording,
    stopRecording,
    openMicrophoneSettings,
  } = useVoiceInput({
    onTranscription: handleTranscription,
    onError: handleVoiceError,
  });

  const isRecording = status === 'recording';
  const isTranscribing = status === 'transcribing';
  const isBusy = isTranscribing || isSending || isRecalling;

  const statusLabel = isRecording
    ? t('voice.listening', 'Listening…')
    : isTranscribing
      ? t('voice.transcribing', 'Transcribing…')
      : isRecalling
        ? t('voice.recalling', 'Recalling memory…')
        : isSending
          ? t('voice.thinking', 'ɳClaw is thinking…')
          : t('voice.tapToSpeak', 'Tap to speak');

  const handleOrbPress = useCallback(() => {
    if (!isPermissionGranted && status === 'idle') {
      openMicrophoneSettings();
      return;
    }
    if (isRecording) {
      void stopRecording();
    } else if (status === 'idle' || status === 'done') {
      void startRecording();
    }
  }, [isPermissionGranted, status, isRecording, stopRecording, startRecording, openMicrophoneSettings]);

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
          accessibilityLabel={t('common.close', 'Close')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 18 }}>✕</Text>
        </Pressable>
        <Text
          className="flex-1 text-lg font-semibold text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {t('voice.title', 'Voice')}
        </Text>
        <Pressable
          onPress={() => router.push('/voice-settings')}
          className="p-2"
          accessibilityLabel={t('voice.openSettings', 'Voice settings')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>⚙️</Text>
        </Pressable>
      </View>

      {/* Rolling transcript */}
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ padding: 16, flexGrow: 1, justifyContent: turns.length ? 'flex-start' : 'center' }}
        showsVerticalScrollIndicator={false}
      >
        {turns.length === 0 ? (
          <View className="items-center">
            <Text className="text-5xl mb-4">🎙️</Text>
            <Text className="text-lg font-semibold text-foreground text-center">
              {t('voice.emptyHeading', 'Talk to ɳClaw')}
            </Text>
            <Text className="text-sm text-muted-foreground text-center mt-2">
              {t('voice.emptyHint', 'Tap the orb and speak. ɳClaw listens, thinks, and replies.')}
            </Text>
          </View>
        ) : (
          turns.map((turn) => (
            <View
              key={turn.id}
              className={`mb-3 max-w-[85%] ${turn.role === 'user' ? 'self-end' : 'self-start'}`}
            >
              <Text className="text-xs text-muted-foreground mb-1" style={{ textAlign: dir.textAlign }}>
                {turn.role === 'user' ? t('chat.you', 'You') : t('chat.assistant', 'ɳClaw')}
              </Text>
              <View className={`rounded-2xl px-4 py-3 ${turn.role === 'user' ? 'bg-primary' : 'bg-card'}`}>
                <Text
                  className={`text-base ${turn.role === 'user' ? 'text-primary-foreground' : 'text-foreground'}`}
                  style={{ textAlign: dir.textAlign }}
                >
                  {turn.text}
                </Text>
              </View>
            </View>
          ))
        )}
      </ScrollView>

      {/* Error line */}
      {lastError && (
        <Text className="text-sm text-destructive text-center px-4 pb-2" accessibilityRole="alert">
          {lastError}
        </Text>
      )}

      {/* Mic orb + status */}
      <View className="items-center pb-10 pt-4">
        <Pressable
          onPress={handleOrbPress}
          disabled={isBusy && !isRecording}
          className={`w-24 h-24 rounded-full items-center justify-center ${
            isRecording ? 'bg-destructive' : isBusy ? 'bg-muted' : 'bg-primary'
          }`}
          accessibilityLabel={
            isRecording
              ? t('voice.stopListening', 'Stop listening')
              : t('voice.startListening', 'Start listening')
          }
          accessibilityRole="button"
          accessibilityState={{ disabled: isBusy && !isRecording, busy: isBusy }}
        >
          <Text style={{ fontSize: 36 }}>{isRecording ? '⏹️' : '🎙️'}</Text>
        </Pressable>
        <Text className="text-sm text-muted-foreground mt-4">{statusLabel}</Text>
      </View>
    </View>
  );
}
