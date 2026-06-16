/**
 * Purpose: Tab navigator layout for the main shell of ɳClaw mobile.
 *   Maps to feature-spec §5 navigation structure: 4 bottom tabs.
 * Inputs:  None — renders tab bar and tab screens.
 * Outputs: Bottom navigation bar with Chat / Memory / Actions / Servers tabs.
 * Constraints: Tab icons must have accessibilityLabel. No hardcoded strings.
 * SPORT: None — SPORT updated in T09.
 */

import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Text } from 'react-native';

/** Simple emoji icon for tabs (placeholder until brand icons land). */
function TabIcon({ emoji, label }: { emoji: string; label: string }) {
  return (
    <Text
      accessibilityLabel={label}
      accessibilityRole="image"
      style={{ fontSize: 20 }}
    >
      {emoji}
    </Text>
  );
}

export default function TabsLayout() {
  const { t } = useTranslation();

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: '#6C3CE1',
        headerShown: false,
      }}
    >
      <Tabs.Screen
        name="chat"
        options={{
          title: t('tabs.chat', 'Chat'),
          tabBarIcon: () => (
            <TabIcon
              emoji="💬"
              label={t('tabs.chat', 'Chat')}
            />
          ),
          tabBarAccessibilityLabel: t('tabs.chat', 'Chat'),
        }}
      />
      <Tabs.Screen
        name="actions"
        options={{
          title: t('tabs.actions', 'Actions'),
          tabBarIcon: () => (
            <TabIcon
              emoji="⚡"
              label={t('tabs.actions', 'Actions')}
            />
          ),
          tabBarAccessibilityLabel: t('tabs.actions', 'Actions'),
        }}
      />
      <Tabs.Screen
        name="memory"
        options={{
          title: t('tabs.memory', 'Memory'),
          tabBarIcon: () => (
            <TabIcon
              emoji="🧠"
              label={t('tabs.memory', 'Memory')}
            />
          ),
          tabBarAccessibilityLabel: t('tabs.memory', 'Memory'),
        }}
      />
      <Tabs.Screen
        name="servers"
        options={{
          title: t('tabs.servers', 'Servers'),
          tabBarIcon: () => (
            <TabIcon
              emoji="🖧"
              label={t('tabs.servers', 'Servers')}
            />
          ),
          tabBarAccessibilityLabel: t('tabs.servers', 'Servers'),
        }}
      />
      {/*
       * history.tsx is a pushed screen (stack navigation into chat history),
       * NOT a standalone tab — hidden from the tab bar per feature-spec §5.
       * Expo Router auto-registers all files in a tabs group, so we must
       * explicitly exclude it via href: null.
       */}
      <Tabs.Screen
        name="history"
        options={{
          href: null,
        }}
      />
    </Tabs>
  );
}
