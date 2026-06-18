/**
 * VoiceSettingsScreen — STT / TTS provider and voice configuration.
 *
 * Purpose: Configure speech-to-text and text-to-speech (feature-spec §1a row
 *   "Voice settings"). Lets the user pick STT/TTS providers, a TTS voice, and
 *   toggle auto-speak of AI replies. Persists config in AsyncStorage. Reached
 *   from the voice conversation screen's settings button.
 *
 * Inputs:  STT provider, TTS provider, voice id, auto-speak toggle. AsyncStorage.
 * Outputs: Voice config form with provider pickers.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: voice-input.tsx (voice conversation), useVoiceInput.ts.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, Pressable, ScrollView, Switch } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';

import { useDirection } from '../lib/useDirection';

const STORAGE_KEY = 'nclaw:voice-settings';

interface VoiceConfig {
  sttProvider: string;
  ttsProvider: string;
  voiceId: string;
  autoSpeak: boolean;
}

const DEFAULT: VoiceConfig = {
  sttProvider: 'whisper',
  ttsProvider: 'piper',
  voiceId: 'default',
  autoSpeak: true,
};

const STT_PROVIDERS = ['whisper', 'system'];
const TTS_PROVIDERS = ['piper', 'elevenlabs', 'system'];

function PickerRow({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: string[];
  value: string;
  onChange: (v: string) => void;
}) {
  const { t } = useTranslation();
  const dir = useDirection();
  return (
    <View className="mb-6">
      <Text className="text-sm font-medium text-foreground mb-2" style={{ textAlign: dir.textAlign }}>
        {label}
      </Text>
      <View className="flex-row flex-wrap gap-2" style={{ flexDirection: dir.flexRow }}>
        {options.map((opt) => {
          const active = value === opt;
          return (
            <Pressable
              key={opt}
              onPress={() => onChange(opt)}
              className={`px-4 py-2 rounded-xl ${active ? 'bg-primary' : 'bg-muted'}`}
              accessibilityLabel={opt}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
            >
              <Text className={`text-sm ${active ? 'text-primary-foreground font-medium' : 'text-muted-foreground'}`}>
                {t(`voiceSettings.provider.${opt}`, opt)}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export default function VoiceSettingsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const [config, setConfig] = useState<VoiceConfig>(DEFAULT);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((raw) => {
        if (raw) setConfig(JSON.parse(raw) as VoiceConfig);
      })
      .catch(() => undefined);
  }, []);

  const persist = useCallback(async (next: VoiceConfig) => {
    setConfig(next);
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }, []);

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
          {t('voiceSettings.title', 'Voice Settings')}
        </Text>
      </View>

      <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }}>
        <PickerRow
          label={t('voiceSettings.stt', 'Speech-to-text provider')}
          options={STT_PROVIDERS}
          value={config.sttProvider}
          onChange={(v) => persist({ ...config, sttProvider: v })}
        />
        <PickerRow
          label={t('voiceSettings.tts', 'Text-to-speech provider')}
          options={TTS_PROVIDERS}
          value={config.ttsProvider}
          onChange={(v) => persist({ ...config, ttsProvider: v })}
        />

        <View className="flex-row items-center justify-between py-3" style={{ flexDirection: dir.flexRow }}>
          <View className="flex-1">
            <Text className="text-base text-foreground" style={{ textAlign: dir.textAlign }}>
              {t('voiceSettings.autoSpeak', 'Auto-speak replies')}
            </Text>
            <Text className="text-sm text-muted-foreground" style={{ textAlign: dir.textAlign }}>
              {t('voiceSettings.autoSpeakHint', 'Read AI responses aloud in voice mode.')}
            </Text>
          </View>
          <Switch
            value={config.autoSpeak}
            onValueChange={(v) => persist({ ...config, autoSpeak: v })}
            accessibilityLabel={t('voiceSettings.autoSpeak', 'Auto-speak replies')}
          />
        </View>
      </ScrollView>
    </View>
  );
}
