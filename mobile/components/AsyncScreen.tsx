/**
 * AsyncScreen — React Native 7-state data-loading wrapper.
 *
 * Purpose: Native (RN) equivalent of @nself/ui AsyncScreen for mobile screens.
 *   Every screen that loads async data wraps its content here so no UI state
 *   (loading / skeleton / empty / data / error / offline / success) is omitted.
 *
 * Inputs:
 *   - status: 'loading' | 'skeleton' | 'empty' | 'error' | 'offline' | 'success' | 'data'
 *   - children: rendered when status === 'data' or 'success'
 *   - error?: Error | string — shown in error state
 *   - onRetry?: () => void — retry callback for error/offline state
 *   - emptyMessage?: string — custom empty state copy
 *   - testID?: string — for accessibility
 *
 * Outputs: The correct state UI; or children for data/success.
 * Constraints:
 *   - All copy via t() — no hardcoded strings.
 *   - All state indicators are WCAG 2.1 AA accessible (accessibilityLabel set).
 *   - No StyleSheet.create — NativeWind className only.
 *
 * SPORT: None — SPORT updated in T09.
 */

import React from 'react';
import {
  View,
  Text,
  ActivityIndicator,
  Pressable,
} from 'react-native';
import { useTranslation } from 'react-i18next';

/** The 7 UI states every data screen must handle. */
export type ScreenStatus =
  | 'loading'
  | 'skeleton'
  | 'empty'
  | 'data'
  | 'error'
  | 'offline'
  | 'success';

export interface AsyncScreenProps {
  /** Current data-fetch status. */
  status: ScreenStatus;
  /** Rendered when status is 'data' or 'success'. */
  children: React.ReactNode;
  /** Error to display in error state. */
  error?: Error | string | null;
  /** Called when the user taps Retry in error/offline state. */
  onRetry?: () => void;
  /** Override the empty-state message. */
  emptyMessage?: string;
  /** Optional test ID (maps to accessibilityLabel on state containers). */
  testID?: string;
}

// ─── State sub-components ──────────────────────────────────────────────────────

function LoadingState({ testID }: { testID?: string }) {
  const { t } = useTranslation();
  return (
    <View
      className="flex-1 items-center justify-center bg-background"
      accessibilityLabel={t('asyncScreen.loading', 'Loading')}
      accessibilityRole="progressbar"
      testID={testID ? `${testID}-loading` : undefined}
    >
      <ActivityIndicator size="large" color="#6C3CE1" />
      <Text className="mt-3 text-sm text-muted-foreground">
        {t('asyncScreen.loading', 'Loading')}
      </Text>
    </View>
  );
}

function SkeletonState({ testID }: { testID?: string }) {
  const { t } = useTranslation();
  return (
    <View
      className="flex-1 p-4 bg-background"
      accessibilityLabel={t('asyncScreen.loading', 'Loading')}
      accessibilityRole="progressbar"
      testID={testID ? `${testID}-skeleton` : undefined}
    >
      {[0, 1, 2, 3, 4].map((i) => (
        <View
          key={i}
          className="h-16 rounded-xl bg-muted mb-3 opacity-60"
          style={{ opacity: 1 - i * 0.15 }}
        />
      ))}
    </View>
  );
}

function EmptyState({
  message,
  testID,
}: {
  message?: string;
  testID?: string;
}) {
  const { t } = useTranslation();
  return (
    <View
      className="flex-1 items-center justify-center bg-background px-8"
      accessibilityLabel={message ?? t('asyncScreen.empty', 'Nothing here yet')}
      testID={testID ? `${testID}-empty` : undefined}
    >
      <Text className="text-4xl mb-4">🗒️</Text>
      <Text className="text-lg font-semibold text-foreground text-center">
        {message ?? t('asyncScreen.empty', 'Nothing here yet')}
      </Text>
      <Text className="text-sm text-muted-foreground text-center mt-2">
        {t('asyncScreen.emptyHint', 'Start a conversation to see it here.')}
      </Text>
    </View>
  );
}

function ErrorState({
  error,
  onRetry,
  testID,
}: {
  error?: Error | string | null;
  onRetry?: () => void;
  testID?: string;
}) {
  const { t } = useTranslation();
  const message =
    error instanceof Error
      ? error.message
      : error ?? t('asyncScreen.errorGeneric', 'Something went wrong.');

  return (
    <View
      className="flex-1 items-center justify-center bg-background px-8"
      accessibilityLabel={t('asyncScreen.errorLabel', 'Error')}
      testID={testID ? `${testID}-error` : undefined}
    >
      <Text className="text-4xl mb-4">⚠️</Text>
      <Text className="text-lg font-semibold text-destructive text-center">
        {t('asyncScreen.errorHeading', 'Something went wrong')}
      </Text>
      <Text className="text-sm text-muted-foreground text-center mt-2">
        {message}
      </Text>
      {onRetry && (
        <Pressable
          onPress={onRetry}
          className="mt-6 px-6 py-3 bg-primary rounded-xl"
          accessibilityLabel={t('asyncScreen.retry', 'Retry')}
          accessibilityRole="button"
        >
          <Text className="text-primary-foreground font-medium">
            {t('asyncScreen.retry', 'Retry')}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

function OfflineState({
  onRetry,
  testID,
}: {
  onRetry?: () => void;
  testID?: string;
}) {
  const { t } = useTranslation();
  return (
    <View
      className="flex-1 items-center justify-center bg-background px-8"
      accessibilityLabel={t('asyncScreen.offlineLabel', 'Offline')}
      testID={testID ? `${testID}-offline` : undefined}
    >
      <Text className="text-4xl mb-4">📡</Text>
      <Text className="text-lg font-semibold text-foreground text-center">
        {t('asyncScreen.offlineHeading', "You're offline")}
      </Text>
      <Text className="text-sm text-muted-foreground text-center mt-2">
        {t('asyncScreen.offlineHint', 'Check your connection and try again.')}
      </Text>
      {onRetry && (
        <Pressable
          onPress={onRetry}
          className="mt-6 px-6 py-3 bg-primary rounded-xl"
          accessibilityLabel={t('asyncScreen.retry', 'Retry')}
          accessibilityRole="button"
        >
          <Text className="text-primary-foreground font-medium">
            {t('asyncScreen.retry', 'Retry')}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

function SuccessState({ testID }: { testID?: string }) {
  const { t } = useTranslation();
  return (
    <View
      className="flex-1 items-center justify-center bg-background"
      accessibilityLabel={t('asyncScreen.success', 'Success')}
      testID={testID ? `${testID}-success` : undefined}
    >
      <Text className="text-5xl mb-3">✅</Text>
      <Text className="text-base font-semibold text-foreground">
        {t('asyncScreen.success', 'Done!')}
      </Text>
    </View>
  );
}

// ─── AsyncScreen ───────────────────────────────────────────────────────────────

/**
 * AsyncScreen wraps any data-driven screen.
 * Show children only when status === 'data' | 'success'.
 *
 * @example
 * <AsyncScreen status={status} onRetry={refetch} error={error}>
 *   <MyContent data={data} />
 * </AsyncScreen>
 */
export function AsyncScreen({
  status,
  children,
  error,
  onRetry,
  emptyMessage,
  testID,
}: AsyncScreenProps): React.ReactElement {
  switch (status) {
    case 'loading':
      return <LoadingState testID={testID} />;
    case 'skeleton':
      return <SkeletonState testID={testID} />;
    case 'empty':
      return <EmptyState message={emptyMessage} testID={testID} />;
    case 'error':
      return <ErrorState error={error} onRetry={onRetry} testID={testID} />;
    case 'offline':
      return <OfflineState onRetry={onRetry} testID={testID} />;
    case 'success':
      return <SuccessState testID={testID} />;
    case 'data':
    default:
      return <>{children}</>;
  }
}
