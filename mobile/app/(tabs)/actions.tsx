/**
 * ActionsScreen — agentic action queue (tab 3, feature-spec §5).
 *
 * Purpose: View and manage pending, active, and completed agentic actions.
 *          Navigation skeleton stub — backend wiring in subsequent S3 tickets.
 * Inputs:  None (stub state — no real data yet).
 * Outputs: TabBar (Pending / Active / History) with empty-state placeholders.
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t() — zero hardcoded strings.
 *   - Matches feature-spec §5 Tab 2 (ActionListScreen).
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */

import React, { useState } from 'react';
import { View, Text, Pressable, FlatList } from 'react-native';
import { useTranslation } from 'react-i18next';

type ActionTab = 'pending' | 'active' | 'history';

const ACTION_TABS: { key: ActionTab; label: string }[] = [
  { key: 'pending', label: 'Pending' },
  { key: 'active', label: 'Active' },
  { key: 'history', label: 'History' },
];

export default function ActionsScreen(): React.JSX.Element {
  const { t } = useTranslation();
  const [activeTab, setActiveTab] = useState<ActionTab>('pending');

  return (
    <View className='flex-1 bg-surface'>
      {/* Tab bar: Pending / Active / History */}
      <View className='flex-row border-b border-slate-700 px-4'>
        {ACTION_TABS.map((tab) => (
          <Pressable
            key={tab.key}
            className={`py-3 mr-6 border-b-2 ${
              activeTab === tab.key ? 'border-brand' : 'border-transparent'
            }`}
            onPress={() => setActiveTab(tab.key)}
            accessibilityRole='tab'
            accessibilityState={{ selected: activeTab === tab.key }}
            accessibilityLabel={t(`actions.tab.${tab.key}`, tab.label)}
          >
            <Text
              className={`text-sm font-medium ${
                activeTab === tab.key ? 'text-brand' : 'text-slate-400'
              }`}
            >
              {t(`actions.tab.${tab.key}`, tab.label)}
            </Text>
          </Pressable>
        ))}
      </View>

      {/* Empty state (wiring in subsequent tickets) */}
      <FlatList
        data={[]}
        renderItem={null}
        ListEmptyComponent={
          <View className='flex-1 items-center justify-center py-24'>
            <Text className='text-2xl mb-3'>⚡</Text>
            <Text className='text-white font-medium text-base mb-1'>
              {t('actions.empty.title', 'No actions yet')}
            </Text>
            <Text className='text-slate-400 text-sm text-center px-8'>
              {t(
                'actions.empty.subtitle',
                'Agentic actions from your AI assistant will appear here.'
              )}
            </Text>
          </View>
        }
        contentContainerStyle={{ flexGrow: 1 }}
      />
    </View>
  );
}
