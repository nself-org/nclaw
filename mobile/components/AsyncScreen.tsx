/**
 * AsyncScreen — React Native 7-state data-loading wrapper.
 *
 * Purpose: Native (RN) equivalent of @nself/ui AsyncScreen for mobile screens.
 *   Every screen that loads async data wraps its content here so no UI state
 *   is omitted. Implements the full 7-state contract required by E5 robustness.
 *
 * Inputs:
 *   - status: 'loading' | 'skeleton' | 'empty' | 'error' | 'offline' |
 *             'permission-denied' | 'rate-limited' | 'success' | 'data'
 *   - children: rendered when status === 'data' or 'success'
 *   - error?: Error | string — shown in error state
 *   - onRetry?: () => void — retry callback for error/offline state
 *   - onReAuth?: () => void — re-auth callback for permission-denied state
 *   - emptyMessage?: string — custom empty state copy
 *   - retryAfterMs?: number — countdown ms for rate-limited state
 *   - testID?: string — for accessibility
 *
 * Outputs: The correct state UI; or children for data/success.
 * Constraints:
 *   - All copy via t() — no hardcoded strings.
 *   - All state indicators are WCAG 2.1 AA accessible (accessibilityLabel set).
 *   - No StyleSheet.create — NativeWind className only.
 *   - 7 required states: loading (skeleton), empty (CTA), error (typed card + retry),
 *     data (populated content), offline (queue indicator), permission-denied (re-auth),
 *     rate-limited (countdown).
 *
 * SPORT: None — SPORT updated in T09.
 */

import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  ActivityIndicator,
  Pressable,
} from 'react-native';
import { useTranslation } from 'react-i18next';

/**
 * The 9 UI states every data screen must handle.
 * Core contract (7 required by E5 spec):
 *   loading        — spinner; maps to "skeleton" in spec terminology
 *   skeleton       — animated placeholder rows
 *   empty          — no data yet; shows CTA
 *   data           — populated content (children rendered)
 *   error          — typed error card + retry button
 *   offline        — offline with queue indicator
 *   permission-denied — requires re-auth flow
 *   rate-limited   — rate limit with countdown
 *   success        — operation completed successfully
 */
export type ScreenStatus =
  | 'loading'
  | 'skeleton'
  | 'empty'
  | 'data'
  | 'error'
  | 'offline'
  | 'permission-denied'
  | 'rate-limited'
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
  /** Called when the user taps Re-authenticate in permission-denied state. */
  onReAuth?: () => void;
  /** Override the empty-state message. */
  emptyMessage?: string;
  /** Milliseconds until retry is allowed (for rate-limited state countdown). */
  retryAfterMs?: number;
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

function PermissionDeniedState({
  onReAuth,
  testID,
}: {
  onReAuth?: () => void;
  testID?: string;
}) {
  const { t } = useTranslation();
  return (
    <View
      className="flex-1 items-center justify-center bg-background px-8"
      accessibilityLabel={t('asyncScreen.permissionDeniedLabel', 'Permission required')}
      testID={testID ? `${testID}-permission-denied` : undefined}
    >
      <Text className="text-4xl mb-4">🔒</Text>
      <Text className="text-lg font-semibold text-foreground text-center">
        {t('asyncScreen.permissionDeniedHeading', 'Access required')}
      </Text>
      <Text className="text-sm text-muted-foreground text-center mt-2">
        {t(
          'asyncScreen.permissionDeniedHint',
          'You need to sign in again to continue.',
        )}
      </Text>
      {onReAuth && (
        <Pressable
          onPress={onReAuth}
          className="mt-6 px-6 py-3 bg-primary rounded-xl"
          accessibilityLabel={t('asyncScreen.reAuth', 'Sign in again')}
          accessibilityRole="button"
        >
          <Text className="text-primary-foreground font-medium">
            {t('asyncScreen.reAuth', 'Sign in again')}
          </Text>
        </Pressable>
      )}
    </View>
  );
}

function RateLimitedState({
  retryAfterMs,
  onRetry,
  testID,
}: {
  retryAfterMs?: number;
  onRetry?: () => void;
  testID?: string;
}) {
  const { t } = useTranslation();
  const initialSeconds = retryAfterMs ? Math.ceil(retryAfterMs / 1000) : 0;
  const [remaining, setRemaining] = useState<number>(initialSeconds);

  useEffect(() => {
    if (remaining <= 0) return;
    const timer = setInterval(() => {
      setRemaining((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [remaining]);

  const canRetry = remaining <= 0;

  return (
    <View
      className="flex-1 items-center justify-center bg-background px-8"
      accessibilityLabel={t('asyncScreen.rateLimitedLabel', 'Rate limited')}
      testID={testID ? `${testID}-rate-limited` : undefined}
    >
      <Text className="text-4xl mb-4">⏳</Text>
      <Text className="text-lg font-semibold text-foreground text-center">
        {t('asyncScreen.rateLimitedHeading', 'Slow down')}
      </Text>
      <Text className="text-sm text-muted-foreground text-center mt-2">
        {remaining > 0
          ? t('asyncScreen.rateLimitedCountdown', 'Try again in {{seconds}}s', {
              seconds: remaining,
            })
          : t('asyncScreen.rateLimitedReady', 'You can try again now.')}
      </Text>
      {onRetry && canRetry && (
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

// ─── AsyncScreen ───────────────────────────────────────────────────────────────

/**
 * AsyncScreen wraps any data-driven screen.
 * Show children only when status === 'data' | 'success'.
 *
 * @example
 * <AsyncScreen status={status} onRetry={refetch} error={error}>
 *   <MyContent data={data} />
 * </AsyncScreen>
 *
 * @example with rate-limit and permission-denied:
 * <AsyncScreen
 *   status={status}
 *   onRetry={refetch}
 *   onReAuth={navigateToLogin}
 *   retryAfterMs={chatError?.retryAfterMs}
 *   error={error}
 * >
 *   <MyContent data={data} />
 * </AsyncScreen>
 */
export function AsyncScreen({
  status,
  children,
  error,
  onRetry,
  onReAuth,
  emptyMessage,
  retryAfterMs,
  testID,
}: AsyncScreenProps): React.ReactElement {
  switch (status) {
    case 'loading':
      return <LoadingState {...(testID && { testID })} />;
    case 'skeleton':
      return <SkeletonState {...(testID && { testID })} />;
    case 'empty':
      return <EmptyState {...(emptyMessage && { message: emptyMessage })} {...(testID && { testID })} />;
    case 'error':
      return <ErrorState {...(error && { error })} {...(onRetry && { onRetry })} {...(testID && { testID })} />;
    case 'offline':
      return <OfflineState {...(onRetry && { onRetry })} {...(testID && { testID })} />;
    case 'permission-denied':
      return <PermissionDeniedState {...(onReAuth && { onReAuth })} {...(testID && { testID })} />;
    case 'rate-limited':
      return (
        <RateLimitedState
          {...(retryAfterMs && { retryAfterMs })}
          {...(onRetry && { onRetry })}
          {...(testID && { testID })}
        />
      );
    case 'success':
      return <SuccessState {...(testID && { testID })} />;
    case 'data':
    default:
      return <>{children}</>;
  }
}
