/**
 * LocalAiScreen — on-device / Ollama local model configuration.
 *
 * Purpose: Settings sub-screen for local LLM config (feature-spec §1a row
 *   "Settings / Local AI"). Lets the user point ɳClaw at a local Ollama endpoint,
 *   pick an installed model, and toggle "prefer local" routing. Persists config in
 *   AsyncStorage. Reached from Settings → AI & Models → Local AI.
 *
 * Inputs:  Ollama base URL, model name, prefer-local toggle. AsyncStorage state.
 *          Model list fetched from {ollamaUrl}/api/tags (documented Ollama contract).
 * Outputs: Local AI config form + discovered model list.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: settings/index.tsx, Ollama /api/tags contract.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, Switch } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import AsyncStorage from '@react-native-async-storage/async-storage';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

const STORAGE_KEY = 'nclaw:local-ai';
const DEFAULT_URL = 'http://localhost:11434';

interface LocalAiConfig {
  ollamaUrl: string;
  model: string;
  preferLocal: boolean;
}

interface OllamaTag {
  name: string;
}

export default function LocalAiScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('data');
  const [config, setConfig] = useState<LocalAiConfig>({ ollamaUrl: DEFAULT_URL, model: '', preferLocal: false });
  const [models, setModels] = useState<string[]>([]);
  const [error, setError] = useState<Error | null>(null);

  // Load persisted config on mount.
  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((raw) => {
        if (raw) setConfig(JSON.parse(raw) as LocalAiConfig);
      })
      .catch(() => undefined);
  }, []);

  const persist = useCallback(async (next: LocalAiConfig) => {
    setConfig(next);
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }, []);

  // Discover installed models from the Ollama endpoint.
  const discoverModels = useCallback(async () => {
    setStatus('loading');
    setError(null);
    try {
      const base = config.ollamaUrl.trim().replace(/\/+$/, '');
      const res = await fetch(`${base}/api/tags`);
      if (!res.ok) throw new Error(t('localAi.discoverFailed', 'Could not reach the local server.'));
      const json = (await res.json()) as { models?: OllamaTag[] };
      setModels((json.models ?? []).map((m) => m.name));
      setStatus('data');
    } catch (err) {
      const isNetwork = err instanceof TypeError;
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus(isNetwork ? 'offline' : 'error');
    }
  }, [config.ollamaUrl, t]);

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
          {t('localAi.title', 'Local AI')}
        </Text>
      </View>

      <AsyncScreen status={status} error={error} onRetry={discoverModels} testID="local-ai">
        <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
          {/* Ollama URL */}
          <View className="mb-4">
            <Text className="text-sm font-medium text-foreground mb-1" style={{ textAlign: dir.textAlign }}>
              {t('localAi.endpoint', 'Local server URL')}
            </Text>
            <TextInput
              value={config.ollamaUrl}
              onChangeText={(v) => persist({ ...config, ollamaUrl: v })}
              placeholder={DEFAULT_URL}
              placeholderTextColor="#888"
              className="bg-card border border-border rounded-xl px-4 py-3 text-base text-foreground"
              style={{ textAlign: dir.textAlign }}
              accessibilityLabel={t('localAi.endpoint', 'Local server URL')}
              keyboardType="url"
              autoCapitalize="none"
              autoCorrect={false}
            />
          </View>

          {/* Discover */}
          <Pressable
            onPress={discoverModels}
            className="py-3 rounded-xl items-center bg-muted mb-6"
            accessibilityLabel={t('localAi.discover', 'Discover models')}
            accessibilityRole="button"
          >
            <Text className="text-sm font-medium text-foreground">{t('localAi.discover', 'Discover models')}</Text>
          </Pressable>

          {/* Model list */}
          {models.length > 0 && (
            <View className="mb-6">
              <Text className="text-sm font-medium text-foreground mb-2" style={{ textAlign: dir.textAlign }}>
                {t('localAi.models', 'Installed models')}
              </Text>
              {models.map((m) => {
                const active = config.model === m;
                return (
                  <Pressable
                    key={m}
                    onPress={() => persist({ ...config, model: m })}
                    className={`flex-row items-center px-4 py-3 rounded-xl border mb-2 ${active ? 'border-primary bg-primary/10' : 'border-border bg-card'}`}
                    accessibilityLabel={m}
                    accessibilityRole="button"
                    accessibilityState={{ selected: active }}
                    style={{ flexDirection: dir.flexRow }}
                  >
                    <Text className="flex-1 text-base text-foreground" style={{ textAlign: dir.textAlign }}>{m}</Text>
                    {active && <Text className="text-primary">✓</Text>}
                  </Pressable>
                );
              })}
            </View>
          )}

          {/* Prefer local toggle */}
          <View className="flex-row items-center justify-between py-3" style={{ flexDirection: dir.flexRow }}>
            <View className="flex-1">
              <Text className="text-base text-foreground" style={{ textAlign: dir.textAlign }}>
                {t('localAi.preferLocal', 'Prefer local model')}
              </Text>
              <Text className="text-sm text-muted-foreground" style={{ textAlign: dir.textAlign }}>
                {t('localAi.preferLocalHint', 'Route inference to the local model when available.')}
              </Text>
            </View>
            <Switch
              value={config.preferLocal}
              onValueChange={(v) => persist({ ...config, preferLocal: v })}
              accessibilityLabel={t('localAi.preferLocal', 'Prefer local model')}
            />
          </View>
        </ScrollView>
      </AsyncScreen>
    </View>
  );
}
