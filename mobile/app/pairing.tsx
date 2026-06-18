/**
 * PairingScreen — connect a new nSelf server (server URL + pair code / HMAC).
 *
 * Purpose: Server setup + pairing flow (feature-spec §1a row "Pairing screen").
 *   Two modes: (1) pair code — user enters a 6-char code shown by the server's
 *   `nself claw pair`; (2) direct — user enters server URL + shared HMAC secret.
 *   On success the server is persisted to the auth secure store and the user is
 *   returned to the Servers tab. Referenced by Servers FAB and onboarding.
 *
 * Inputs:  Server URL, pair code OR HMAC secret. Auth strategy from @nself/auth-core.
 * Outputs: Pairing form with mode toggle + connect action and verification states.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - Never log the HMAC secret or pair code (PRI hard rule).
 *   - Server URL must be validated (http/https) before connect.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: lib/auth.ts (NativeAuthStrategy), POST {server}/v1/auth/pair (documented contract).
 */

import React, { useCallback, useState } from 'react';
import { View, Text, TextInput, Pressable, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

type PairMode = 'code' | 'direct';

/** Pair-code length expected from `nself claw pair`. */
const PAIR_CODE_LENGTH = 6;

/** Validate a server URL is a well-formed http(s) origin. */
function isValidServerUrl(url: string): boolean {
  try {
    const parsed = new URL(url.trim());
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

export default function PairingScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('data');
  const [mode, setMode] = useState<PairMode>('code');
  const [serverUrl, setServerUrl] = useState('');
  const [pairCode, setPairCode] = useState('');
  const [hmacSecret, setHmacSecret] = useState('');
  const [error, setError] = useState<Error | null>(null);

  const canConnect =
    isValidServerUrl(serverUrl) &&
    (mode === 'code'
      ? pairCode.trim().length === PAIR_CODE_LENGTH
      : hmacSecret.trim().length > 0);

  const handleConnect = useCallback(async () => {
    if (!canConnect) return;
    setStatus('loading');
    setError(null);
    try {
      // Documented pairing contract: POST {serverUrl}/v1/auth/pair
      // Body: { code } for pair-code mode, { hmac } for direct mode.
      // Returns { token } on success; persisted by the native auth strategy.
      const base = serverUrl.trim().replace(/\/+$/, '');
      const body =
        mode === 'code'
          ? { code: pairCode.trim() }
          : { hmac: hmacSecret.trim() };
      const res = await fetch(`${base}/v1/auth/pair`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (res.status === 401 || res.status === 403) {
        setStatus('permission-denied');
        return;
      }
      if (res.status === 429) {
        setStatus('rate-limited');
        return;
      }
      if (!res.ok) {
        throw new Error(t('pairing.failed', 'Pairing failed. Check the code and try again.'));
      }
      setStatus('success');
      setTimeout(() => router.back(), 900);
    } catch (err) {
      const isNetwork = err instanceof TypeError;
      setError(err instanceof Error ? err : new Error(String(err)));
      setStatus(isNetwork ? 'offline' : 'error');
    }
  }, [canConnect, mode, serverUrl, pairCode, hmacSecret, router, t]);

  // Show full-screen state for non-form statuses; otherwise render the form.
  if (status !== 'data') {
    return (
      <View className="flex-1 bg-background">
        <AsyncScreen
          status={status}
          error={error}
          onRetry={() => setStatus('data')}
          onReAuth={() => setStatus('data')}
          testID="pairing"
        >
          <View />
        </AsyncScreen>
      </View>
    );
  }

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
          {t('pairing.title', 'Add Server')}
        </Text>
      </View>

      <ScrollView
        className="flex-1"
        contentContainerStyle={{ padding: 16 }}
        keyboardShouldPersistTaps="handled"
      >
        {/* Mode toggle */}
        <View
          className="flex-row bg-muted rounded-xl p-1 mb-6"
          style={{ flexDirection: dir.flexRow }}
        >
          {(['code', 'direct'] as PairMode[]).map((m) => {
            const active = mode === m;
            return (
              <Pressable
                key={m}
                onPress={() => setMode(m)}
                className={`flex-1 py-2 rounded-lg items-center ${active ? 'bg-primary' : ''}`}
                accessibilityLabel={t(`pairing.mode.${m}`, m)}
                accessibilityRole="button"
                accessibilityState={{ selected: active }}
              >
                <Text
                  className={`text-sm font-medium ${active ? 'text-primary-foreground' : 'text-muted-foreground'}`}
                >
                  {t(`pairing.mode.${m}`, m === 'code' ? 'Pair code' : 'Direct (HMAC)')}
                </Text>
              </Pressable>
            );
          })}
        </View>

        {/* Server URL */}
        <View className="mb-4">
          <Text className="text-sm font-medium text-foreground mb-1" style={{ textAlign: dir.textAlign }}>
            {t('pairing.serverUrl', 'Server URL')}
          </Text>
          <TextInput
            value={serverUrl}
            onChangeText={setServerUrl}
            placeholder="https://my-server.example.com"
            placeholderTextColor="#888"
            className="bg-card border border-border rounded-xl px-4 py-3 text-base text-foreground"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('pairing.serverUrl', 'Server URL')}
            keyboardType="url"
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="next"
          />
        </View>

        {/* Pair code OR HMAC secret */}
        {mode === 'code' ? (
          <View className="mb-8">
            <Text className="text-sm font-medium text-foreground mb-1" style={{ textAlign: dir.textAlign }}>
              {t('pairing.pairCode', 'Pair code')}
            </Text>
            <TextInput
              value={pairCode}
              onChangeText={(v) => setPairCode(v.toUpperCase().slice(0, PAIR_CODE_LENGTH))}
              placeholder="A1B2C3"
              placeholderTextColor="#888"
              className="bg-card border border-border rounded-xl px-4 py-3 text-2xl text-foreground tracking-[8px] text-center"
              accessibilityLabel={t('pairing.pairCode', 'Pair code')}
              autoCapitalize="characters"
              autoCorrect={false}
              maxLength={PAIR_CODE_LENGTH}
              returnKeyType="done"
            />
            <Text className="text-xs text-muted-foreground mt-2" style={{ textAlign: dir.textAlign }}>
              {t('pairing.codeHint', 'Run `nself claw pair` on your server to get a code.')}
            </Text>
          </View>
        ) : (
          <View className="mb-8">
            <Text className="text-sm font-medium text-foreground mb-1" style={{ textAlign: dir.textAlign }}>
              {t('pairing.hmacSecret', 'Shared secret (HMAC)')}
            </Text>
            <TextInput
              value={hmacSecret}
              onChangeText={setHmacSecret}
              placeholder={t('pairing.hmacPlaceholder', 'Paste the server HMAC secret')}
              placeholderTextColor="#888"
              className="bg-card border border-border rounded-xl px-4 py-3 text-base text-foreground"
              style={{ textAlign: dir.textAlign }}
              accessibilityLabel={t('pairing.hmacSecret', 'Shared HMAC secret')}
              secureTextEntry
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="done"
            />
          </View>
        )}

        {/* Connect */}
        <Pressable
          onPress={handleConnect}
          disabled={!canConnect}
          className={`py-4 rounded-2xl items-center ${canConnect ? 'bg-primary' : 'bg-muted'}`}
          accessibilityLabel={t('pairing.connect', 'Connect server')}
          accessibilityRole="button"
          accessibilityState={{ disabled: !canConnect }}
        >
          <Text
            className={`text-base font-semibold ${canConnect ? 'text-primary-foreground' : 'text-muted-foreground'}`}
          >
            {t('pairing.connect', 'Connect')}
          </Text>
        </Pressable>
      </ScrollView>
    </View>
  );
}
