/**
 * ApiKeysScreen — per-provider API key management.
 *
 * Purpose: Manage BYO-key API credentials per AI provider (feature-spec §1a row
 *   "API Keys"). Keys are stored in the on-device secure vault via the libnclaw
 *   JSI seam (vaultSet/vaultGet/vaultDelete) — never in plain storage, never logged.
 *   Reached from Settings → AI & Models → API Keys.
 *
 * Inputs:  Provider list (static) · vault state via NativeNclaw vault JSI.
 * Outputs: Per-provider row with masked key, set/clear actions, and validity badge.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - NEVER render the full key after save — show masked preview only.
 *   - NEVER log key material (PRI hard rule).
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: NativeNclaw vault JSI (vaultSet/vaultGet/vaultDelete), settings/index.tsx.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, TextInput, Pressable, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { NativeNclaw } from '@nself/native-bridge';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

/** Supported BYO-key providers. Vault key = `apikey:{id}`. */
const PROVIDERS: { id: string; label: string; placeholder: string }[] = [
  { id: 'openai', label: 'OpenAI', placeholder: 'sk-...' },
  { id: 'anthropic', label: 'Anthropic', placeholder: 'sk-ant-...' },
  { id: 'google', label: 'Google AI', placeholder: 'AIza...' },
  { id: 'openrouter', label: 'OpenRouter', placeholder: 'sk-or-...' },
  { id: 'groq', label: 'Groq', placeholder: 'gsk_...' },
];

/** Mask a stored key for display: keep last 4 chars only. */
function maskKey(key: string): string {
  if (key.length <= 4) return '••••';
  return `••••••${key.slice(-4)}`;
}

interface ProviderState {
  /** Masked preview of the stored key, or null when none set. */
  masked: string | null;
  /** Draft input value (cleared after save). */
  draft: string;
}

export default function ApiKeysScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('loading');
  const [error, setError] = useState<Error | null>(null);
  const [providers, setProviders] = useState<Record<string, ProviderState>>({});

  // Load existing keys from the secure vault (masked) on mount.
  const loadKeys = useCallback(async () => {
    setStatus('loading');
    setError(null);
    try {
      await NativeNclaw.vault.initVault('nclaw');
      const next: Record<string, ProviderState> = {};
      for (const p of PROVIDERS) {
        const stored = await NativeNclaw.vault.vaultGet(`apikey:${p.id}`);
        next[p.id] = { masked: stored ? maskKey(stored) : null, draft: '' };
      }
      setProviders(next);
      setStatus('data');
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus('error');
    }
  }, []);

  useEffect(() => {
    void loadKeys();
  }, [loadKeys]);

  const handleDraftChange = useCallback((id: string, value: string) => {
    setProviders((prev) => ({
      ...prev,
      [id]: { ...(prev[id] ?? { masked: null, draft: '' }), draft: value },
    }));
  }, []);

  const handleSave = useCallback(async (id: string) => {
    const draft = providers[id]?.draft?.trim();
    if (!draft) return;
    try {
      await NativeNclaw.vault.vaultSet(`apikey:${id}`, draft);
      setProviders((prev) => ({
        ...prev,
        [id]: { masked: maskKey(draft), draft: '' },
      }));
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus('error');
    }
  }, [providers]);

  const handleClear = useCallback(async (id: string) => {
    try {
      await NativeNclaw.vault.vaultDelete(`apikey:${id}`);
      setProviders((prev) => ({ ...prev, [id]: { masked: null, draft: '' } }));
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus('error');
    }
  }, []);

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
        <Text className="flex-1 text-xl font-bold text-foreground" style={{ textAlign: dir.textAlign }}>
          {t('apiKeys.title', 'API Keys')}
        </Text>
      </View>

      <AsyncScreen
        status={status}
        error={error}
        onRetry={loadKeys}
        testID="api-keys"
      >
        <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
          <Text className="text-sm text-muted-foreground mb-4" style={{ textAlign: dir.textAlign }}>
            {t('apiKeys.intro', 'Bring your own API keys. Keys are stored encrypted on-device and never leave it.')}
          </Text>

          {PROVIDERS.map((p) => {
            const state = providers[p.id] ?? { masked: null, draft: '' };
            return (
              <View key={p.id} className="mb-5 rounded-xl border border-border p-4 bg-card">
                <View className="flex-row items-center mb-2" style={{ flexDirection: dir.flexRow }}>
                  <Text className="flex-1 text-base font-medium text-foreground" style={{ textAlign: dir.textAlign }}>
                    {p.label}
                  </Text>
                  {state.masked ? (
                    <View className="px-2 py-0.5 rounded-full bg-green-500/15">
                      <Text className="text-xs text-green-600 font-medium">
                        {t('apiKeys.set', 'Set')} · {state.masked}
                      </Text>
                    </View>
                  ) : (
                    <View className="px-2 py-0.5 rounded-full bg-muted">
                      <Text className="text-xs text-muted-foreground">{t('apiKeys.notSet', 'Not set')}</Text>
                    </View>
                  )}
                </View>

                <View className="flex-row items-center gap-2" style={{ flexDirection: dir.flexRow }}>
                  <TextInput
                    value={state.draft}
                    onChangeText={(v) => handleDraftChange(p.id, v)}
                    placeholder={p.placeholder}
                    placeholderTextColor="#888"
                    className="flex-1 bg-background border border-border rounded-xl px-3 py-2 text-base text-foreground"
                    style={{ textAlign: dir.textAlign }}
                    accessibilityLabel={t('apiKeys.inputLabel', '{{provider}} API key', { provider: p.label })}
                    secureTextEntry
                    autoCapitalize="none"
                    autoCorrect={false}
                  />
                  <Pressable
                    onPress={() => handleSave(p.id)}
                    disabled={!state.draft.trim()}
                    className={`px-4 py-2 rounded-xl ${state.draft.trim() ? 'bg-primary' : 'bg-muted'}`}
                    accessibilityLabel={t('apiKeys.save', 'Save {{provider}} key', { provider: p.label })}
                    accessibilityRole="button"
                    accessibilityState={{ disabled: !state.draft.trim() }}
                  >
                    <Text className={`text-sm font-medium ${state.draft.trim() ? 'text-primary-foreground' : 'text-muted-foreground'}`}>
                      {t('apiKeys.save', 'Save')}
                    </Text>
                  </Pressable>
                </View>

                {state.masked && (
                  <Pressable
                    onPress={() => handleClear(p.id)}
                    className="mt-2 self-start"
                    accessibilityLabel={t('apiKeys.clear', 'Remove {{provider}} key', { provider: p.label })}
                    accessibilityRole="button"
                  >
                    <Text className="text-sm text-destructive">{t('apiKeys.clear', 'Remove key')}</Text>
                  </Pressable>
                )}
              </View>
            );
          })}
        </ScrollView>
      </AsyncScreen>
    </View>
  );
}
