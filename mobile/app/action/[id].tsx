/**
 * ActionDetailScreen — agentic action detail + executor controls.
 *
 * Purpose: Detail view for a single queued/active AI action (feature-spec §1a row
 *   "Action detail"). Shows the action type, target, status, payload, and the
 *   confirmation/approve + cancel controls. Reached from the Actions tab.
 *
 * Inputs:  Route param `id` (action UUID). Action via ACTION_DETAIL query;
 *          approve/cancel via ACTION_SET_STATUS mutation (documented contract).
 * Outputs: Action metadata + payload + approve/cancel actions.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - Destructive (cancel) confirmed via Alert.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: (tabs)/actions.tsx, Hasura nclaw_actions.
 */

import React, { useCallback } from 'react';
import { View, Text, Pressable, ScrollView, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { gql, useQuery, useMutation } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';

/** ACTION_DETAIL — load a single agentic action by id. */
const ACTION_DETAIL = gql`
  query ActionDetail($id: uuid!) {
    nclaw_actions_by_pk(id: $id) {
      id
      action_type
      target
      status
      payload
      created_at
    }
  }
`;

/** ACTION_SET_STATUS — approve or cancel an action. */
const ACTION_SET_STATUS = gql`
  mutation ActionSetStatus($id: uuid!, $status: String!) {
    update_nclaw_actions_by_pk(pk_columns: { id: $id }, _set: { status: $status }) {
      id
      status
    }
  }
`;

interface ActionRow {
  id: string;
  action_type: string;
  target: string | null;
  status: string;
  payload: Record<string, unknown> | null;
  created_at: string;
}

interface ActionDetailData {
  nclaw_actions_by_pk: ActionRow | null;
}

export default function ActionDetailScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();
  const { id } = useLocalSearchParams<{ id: string }>();
  const actionId = typeof id === 'string' ? id : '';

  const [result, refetch] = useQuery<ActionDetailData>({
    query: ACTION_DETAIL,
    variables: { id: actionId },
    pause: !actionId,
  });
  const [, setStatusMutation] = useMutation(ACTION_SET_STATUS);

  const action = result.data?.nclaw_actions_by_pk ?? null;

  const status: ScreenStatus = result.fetching
    ? 'loading'
    : result.error
      ? 'error'
      : !action
        ? 'empty'
        : 'data';

  const handleApprove = useCallback(async () => {
    await setStatusMutation({ id: actionId, status: 'approved' });
    refetch({ requestPolicy: 'network-only' });
  }, [actionId, setStatusMutation, refetch]);

  const handleCancel = useCallback(() => {
    Alert.alert(
      t('actionDetail.cancelTitle', 'Cancel this action?'),
      t('actionDetail.cancelBody', 'The AI will not execute this action.'),
      [
        { text: t('common.cancel', 'Keep'), style: 'cancel' },
        {
          text: t('actionDetail.confirmCancel', 'Cancel action'),
          style: 'destructive',
          onPress: async () => {
            await setStatusMutation({ id: actionId, status: 'cancelled' });
            router.back();
          },
        },
      ],
    );
  }, [actionId, setStatusMutation, router, t]);

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
          {t('actionDetail.title', 'Action')}
        </Text>
      </View>

      <AsyncScreen
        status={status}
        error={result.error ?? null}
        onRetry={() => refetch({ requestPolicy: 'network-only' })}
        onReAuth={() => router.push('/auth/login')}
        testID="action-detail"
        emptyMessage={t('actionDetail.notFound', 'Action not found')}
      >
        {action && (
          <ScrollView className="flex-1" contentContainerStyle={{ padding: 16 }}>
            {/* Type + status */}
            <View className="flex-row items-center mb-4" style={{ flexDirection: dir.flexRow }}>
              <Text className="text-2xl mr-3">⚡</Text>
              <View className="flex-1">
                <Text className="text-lg font-semibold text-foreground" style={{ textAlign: dir.textAlign }}>
                  {action.action_type}
                </Text>
                <Text className="text-sm text-muted-foreground" style={{ textAlign: dir.textAlign }}>
                  {t(`actionDetail.status.${action.status}`, action.status)}
                </Text>
              </View>
            </View>

            {/* Target */}
            {action.target && (
              <View className="rounded-xl bg-card border border-border p-4 mb-4">
                <Text className="text-xs text-muted-foreground mb-1" style={{ textAlign: dir.textAlign }}>
                  {t('actionDetail.target', 'Target')}
                </Text>
                <Text className="text-base text-foreground" style={{ textAlign: dir.textAlign }}>{action.target}</Text>
              </View>
            )}

            {/* Payload */}
            {action.payload && (
              <View className="rounded-xl bg-card border border-border p-4 mb-4">
                <Text className="text-xs text-muted-foreground mb-1" style={{ textAlign: dir.textAlign }}>
                  {t('actionDetail.payload', 'Details')}
                </Text>
                <Text className="text-sm text-foreground font-mono">
                  {JSON.stringify(action.payload, null, 2)}
                </Text>
              </View>
            )}

            {/* Controls */}
            {action.status === 'pending' && (
              <View className="gap-3 mt-2">
                <Pressable
                  onPress={handleApprove}
                  className="py-4 rounded-2xl items-center bg-primary"
                  accessibilityLabel={t('actionDetail.approve', 'Approve action')}
                  accessibilityRole="button"
                >
                  <Text className="text-base font-semibold text-primary-foreground">
                    {t('actionDetail.approve', 'Approve')}
                  </Text>
                </Pressable>
                <Pressable
                  onPress={handleCancel}
                  className="py-4 rounded-2xl items-center border border-destructive"
                  accessibilityLabel={t('actionDetail.confirmCancel', 'Cancel action')}
                  accessibilityRole="button"
                >
                  <Text className="text-base font-medium text-destructive">
                    {t('actionDetail.confirmCancel', 'Cancel action')}
                  </Text>
                </Pressable>
              </View>
            )}
          </ScrollView>
        )}
      </AsyncScreen>
    </View>
  );
}
