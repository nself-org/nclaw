/**
 * ServersScreen — manage paired nSelf servers (tab 4).
 *
 * Purpose: Lists all paired servers with connection-status indicators.
 *   FAB to add a new server. Swipe-to-remove. Tap to switch active server.
 *
 * Inputs:  Server list from local state stub.
 * Outputs: Server list with status dots and add FAB.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useState } from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';

interface ServerEntry {
  id: string;
  label: string;
  address: string;
  status: 'connected' | 'connecting' | 'offline' | 'error';
  isActive: boolean;
}

const STATUS_COLORS: Record<ServerEntry['status'], string> = {
  connected: '#22c55e',
  connecting: '#f59e0b',
  offline: '#6b7280',
  error: '#ef4444',
};

const STUB_SERVERS: ServerEntry[] = [];

export default function ServersScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const [status] = useState<ScreenStatus>('data');
  const [servers] = useState<ServerEntry[]>(STUB_SERVERS);

  return (
    <View className="flex-1 bg-background">
      {/* Header */}
      <View
        className="px-4 pt-4 pb-2 border-b border-border"
        style={{ flexDirection: dir.flexRow, alignItems: 'center' }}
      >
        <Text
          className="flex-1 text-xl font-bold text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {t('servers.title', 'Servers')}
        </Text>
      </View>

      <AsyncScreen status={status} testID="servers">
        {servers.length === 0 ? (
          <View className="flex-1 items-center justify-center px-8">
            <Text className="text-4xl mb-4">🖥️</Text>
            <Text className="text-lg font-semibold text-foreground text-center">
              {t('servers.empty', 'No servers paired')}
            </Text>
            <Text className="text-sm text-muted-foreground text-center mt-2">
              {t('servers.emptyHint', 'Add a server to get started.')}
            </Text>
          </View>
        ) : (
          <FlatList<ServerEntry>
            data={servers}
            keyExtractor={(item: ServerEntry) => item.id}
            renderItem={({ item }: { item: ServerEntry }) => (
              <Pressable
                className="flex-row items-center px-4 py-4 border-b border-border bg-background"
                accessibilityLabel={`${item.label} — ${t(`servers.status.${item.status}`, item.status)}`}
                accessibilityRole="button"
                style={{ flexDirection: dir.flexRow }}
              >
                {/* Status dot */}
                <View
                  className="w-3 h-3 rounded-full"
                  style={{ backgroundColor: STATUS_COLORS[item.status] }}
                  accessibilityLabel={t(`servers.status.${item.status}`, item.status)}
                />
                <View className="flex-1 ml-3">
                  <Text
                    className="text-base font-medium text-foreground"
                    style={{ textAlign: dir.textAlign }}
                  >
                    {item.label}
                  </Text>
                  <Text
                    className="text-sm text-muted-foreground"
                    style={{ textAlign: dir.textAlign }}
                  >
                    {item.address}
                  </Text>
                </View>
                {item.isActive && (
                  <Text className="text-xs text-primary font-medium">
                    {t('servers.active', 'Active')}
                  </Text>
                )}
              </Pressable>
            )}
            showsVerticalScrollIndicator={false}
          />
        )}
      </AsyncScreen>

      {/* FAB — add server */}
      <Pressable
        onPress={() => router.push('/pairing')}
        className="absolute bottom-6 right-6 w-14 h-14 bg-primary rounded-full items-center justify-center shadow-lg"
        accessibilityLabel={t('servers.addServer', 'Add server')}
        accessibilityRole="button"
      >
        <Text className="text-primary-foreground text-2xl font-light">+</Text>
      </Pressable>
    </View>
  );
}
