/**
 * BiometricLockScreen — Full-screen overlay blocking app until biometric auth succeeds.
 *
 * Purpose: Display a branded lock screen with Face ID/fingerprint prompt.
 *   Prevents app content from being visible until user authenticates.
 * Inputs: isLocked (bool), onAuthenticate (callback on success), onCancel (optional).
 * Outputs: Modal-like full-screen View blocking interaction below.
 * Constraints:
 *   - Renders above all other content when isLocked=true.
 *   - NativeWind ClassNames only (no StyleSheet.create).
 *   - Accessible: button has accessibilityLabel and role.
 *   - RTL: layout respects useDirection().
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-biometric-lock-screen
 */

import React, { useCallback } from 'react';
import { View, Text, Pressable, ActivityIndicator } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useDirection } from '../lib/useDirection';

export interface BiometricLockScreenProps {
  /** Whether the lock screen should be shown. */
  isLocked: boolean;
  /** Callback when authenticate button is pressed. */
  onAuthenticate: () => Promise<boolean>;
  /** Optional callback on cancel (optional; defaults to no-op). */
  onCancel?: () => void;
  /** Custom prompt message (defaults to 'Authenticate'). */
  promptMessage?: string;
}

export function BiometricLockScreen({
  isLocked,
  onAuthenticate,
  onCancel,
  promptMessage,
}: BiometricLockScreenProps) {
  const { t } = useTranslation();
  const dir = useDirection();
  const [isAuthenticating, setIsAuthenticating] = React.useState(false);
  const [authError, setAuthError] = React.useState<string | null>(null);

  const handleAuthenticate = useCallback(async () => {
    if (isAuthenticating) return;

    setIsAuthenticating(true);
    setAuthError(null);

    try {
      const success = await onAuthenticate();
      if (!success) {
        setAuthError(t('biometric.authFailed', 'Authentication failed. Please try again.'));
      }
    } catch (err) {
      setAuthError(t('biometric.error', 'An error occurred. Please try again.'));
      console.error('[BiometricLockScreen] Auth error:', err);
    } finally {
      setIsAuthenticating(false);
    }
  }, [isAuthenticating, onAuthenticate, t]);

  const handleCancel = useCallback(() => {
    onCancel?.();
  }, [onCancel]);

  // Don't render if not locked
  if (!isLocked) {
    return null;
  }

  return (
    <View
      className="absolute inset-0 bg-background flex items-center justify-center z-50"
      testID="biometric-lock-screen"
    >
      {/* Content: logo + message + button */}
      <View className="flex items-center gap-6 px-6">
        {/* Logo placeholder: ɳ symbol */}
        <Text className="text-6xl font-bold text-primary">ɳ</Text>

        {/* App name */}
        <Text className="text-2xl font-bold text-foreground">
          {t('app.name', 'ɳClaw')}
        </Text>

        {/* Prompt message */}
        <Text
          className="text-center text-base text-muted-foreground mt-4"
          style={{ textAlign: dir.textAlign }}
        >
          {promptMessage || t('biometric.prompt', 'Authenticate to continue')}
        </Text>

        {/* Error message */}
        {authError && (
          <Text className="text-center text-sm text-destructive mt-2">
            {authError}
          </Text>
        )}

        {/* Authenticate button */}
        <Pressable
          onPress={handleAuthenticate}
          disabled={isAuthenticating}
          className={`w-full mt-6 px-6 py-3 rounded-lg ${
            isAuthenticating ? 'bg-muted' : 'bg-primary'
          } items-center justify-center`}
          accessibilityLabel={t('biometric.unlock', 'Unlock with biometrics')}
          accessibilityRole="button"
          accessibilityState={{ disabled: isAuthenticating }}
        >
          {isAuthenticating ? (
            <ActivityIndicator size="small" color="#FFFFFF" />
          ) : (
            <Text className="text-base font-semibold text-primary-foreground">
              {t('biometric.unlockButton', 'Unlock')}
            </Text>
          )}
        </Pressable>

        {/* Cancel button (optional) */}
        {onCancel && (
          <Pressable
            onPress={handleCancel}
            disabled={isAuthenticating}
            className="mt-3 px-6 py-2"
            accessibilityLabel={t('common.cancel', 'Cancel')}
            accessibilityRole="button"
          >
            <Text className="text-base text-muted-foreground">
              {t('common.cancel', 'Cancel')}
            </Text>
          </Pressable>
        )}
      </View>
    </View>
  );
}
