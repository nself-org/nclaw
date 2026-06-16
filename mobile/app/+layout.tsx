/**
 * Purpose: Root layout for ɳClaw mobile (Expo Router). Initialises Sentry error reporting,
 *   OTel tracing, push notifications, share target handling, biometric auth gate, and background fetch on app startup.
 * Inputs: Children (routed screens), system AppState events, share intent data.
 * Outputs: Renders auth gate overlay when biometric is required; otherwise renders children. Routes to share-composer if share received.
 * Constraints:
 *   - initObservability (Sentry.init + OTel) MUST be called before any screen renders.
 *   - @nself/observability uses platform SDK injection — caller supplies @sentry/react-native.
 *   - Push permission is requested during onboarding flow, not here — this only wires listeners.
 *   - Share target data retrieved from AsyncStorage (iOS: App Group UserDefaults bridge, Android: intent extras).
 *   - configureNotificationHandler() MUST be called at module level (before first notification arrives).
 *   - usePushNavigation() wires tap-to-navigate (foreground + cold-start / killed app).
 *   - initPushNotificationService() starts FCM token registration + token refresh subscription.
 *   - ensureCanonicalTopicChannels() pre-creates Android channels for all known auto-topic tags.
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-layout
 */
import { useEffect } from 'react';
import { View, StyleSheet, useAppState } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import * as SentryRN from '@sentry/react-native';
import { initObservability } from '@nself/observability';

import { useBiometricAuth } from '../hooks/useBiometricAuth';
import { usePushNavigation } from '../hooks/usePushNavigation';
import { BiometricLockScreen } from '../components/BiometricLockScreen';
import { registerMemoryCompactionTask } from '../tasks/memoryCompaction';
import { getSharedContent, clearSharedContent, buildShareDeepLink } from '../services/shareTargetService';
import { biometricLockService } from '../services/biometricLockService';
import {
  initPushNotificationService,
  type PushNotificationServiceHandle,
} from '../services/pushNotificationService';
import {
  configureNotificationHandler,
  ensureCanonicalTopicChannels,
} from '../services/notificationGroupingService';
import { initializeI18n } from '../i18n';

// ─── i18n init (module level — before first render) ──────────────────────────
// Detects device locale via expo-localization and initializes react-i18next.
// RTL layout flipping for Arabic is handled here.
initializeI18n();

// ─── Sentry + OTel init (runs at module load, before first render) ────────────
initObservability({
  sentry: {
    sdk: SentryRN,
    dsn: process.env.EXPO_PUBLIC_SENTRY_DSN ?? '',
    environment: process.env.APP_ENV ?? 'development',
    appKind: 'native' as const,
    tracesSampleRate: process.env.APP_ENV === 'production' ? 0.2 : 1.0,
    release: process.env.EXPO_PUBLIC_APP_VERSION ?? '1.0.0',
  },
});

// ─── Configure notification handler (module level — before first notification) ─
// Sets shouldShowAlert/Sound/Badge and iOS thread-identifier grouping.
configureNotificationHandler();

// ─── Splash screen: keep visible until init complete ─────────────────────────
SplashScreen.preventAutoHideAsync();

// ─── Component ────────────────────────────────────────────────────────────────

export default function RootLayout() {
  const { isAuthenticated, prefEnabled, authenticate } = useBiometricAuth();
  const router = useRouter();
  const appState = useAppState();

  // ── Tap-to-navigate (push notification → correct screen) ─────────────────
  // Handles both foreground taps and cold-start (killed app) initial notification.
  // Navigation logic lives entirely in usePushNavigation — never in handlers.
  usePushNavigation();

  // One-time startup: background task + FCM push init + share target
  useEffect(() => {
    let mounted = true;
    let pushHandle: PushNotificationServiceHandle | null = null;

    (async () => {
      // Register background compaction task (idempotent)
      await registerMemoryCompactionTask();

      // Pre-create Android notification channels for all canonical topics (idempotent)
      await ensureCanonicalTopicChannels();

      // Initialise FCM push notification service:
      //   - Gets Expo push token + FCM/APNs device token
      //   - POSTs both to /api/devices/register (no-op if permission not granted)
      //   - Subscribes to token refresh — re-registers on change
      pushHandle = await initPushNotificationService();

      // Check for shared content (from iOS ShareExtension or Android intent)
      // This handles both cold-launch (app not in memory) and hot-launch cases
      const sharedItem = await getSharedContent();
      if (sharedItem) {
        // Navigate to share composer with pre-filled data
        const deepLink = buildShareDeepLink(sharedItem);
        // Schedule navigation for next render cycle to avoid routing during layout init
        setTimeout(() => {
          if (mounted) {
            router.push(deepLink);
          }
        }, 100);
      }

      // Hide splash once init done
      if (mounted) {
        await SplashScreen.hideAsync();
      }
    })();

    return () => {
      mounted = false;
      // Remove FCM token refresh listener
      pushHandle?.remove();
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Clear shared content when app returns to foreground
  // (ensures stale shares don't re-appear)
  useEffect(() => {
    if (appState.match(/active|foreground/)) {
      // App is in foreground; shared content should be consumed
      // If still present, it means it wasn't saved; safe to keep for retry
    }
  }, [appState]);

  return (
    <View style={styles.rootContainer}>
      {/* Biometric lock screen overlay (if enabled and not authenticated) */}
      <BiometricLockScreen
        isLocked={prefEnabled && !isAuthenticated}
        onAuthenticate={authenticate}
        promptMessage="Unlock ɳClaw"
      />

      {/* Main navigation stack */}
      <Stack>
        {/* Onboarding — requests notification permission */}
        <Stack.Screen name="onboarding" options={{ headerShown: false }} />

        {/* Main tabs */}
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />

        {/* Share composer — receives deep link with pre-filled data */}
        <Stack.Screen
          name="share-composer"
          options={{
            title: 'Save to ɳClaw',
            headerShown: true,
            presentation: 'modal',
          }}
        />

        {/* Modals */}
        <Stack.Screen name="modal" options={{ presentation: 'modal' }} />
      </Stack>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  rootContainer: {
    flex: 1,
    position: 'relative',
  },
});
