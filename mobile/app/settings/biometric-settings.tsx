/**
 * BiometricSettingsScreen — Enable/disable biometric app lock.
 *
 * Purpose: Settings sub-screen for Face ID / fingerprint authentication preference.
 *   Shows toggle, device status, and explanation text.
 * Inputs:  Device biometric enrollment status from biometricLockService.
 * Outputs: Toggle state persisted to secure storage; preference reflected on next resume.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All text via t().
 *   - Disable toggle if device has no biometrics (show explanation).
 *   - Every interactive element has accessibilityLabel + accessibilityRole.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-biometric-settings
 */

import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  Switch,
  ActivityIndicator,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import { AsyncScreen, type ScreenStatus } from '../../components/AsyncScreen';
import { useDirection } from '../../lib/useDirection';
import { biometricLockService } from '../../services/biometricLockService';

export default function BiometricSettingsScreen() {
  const { t } = useTranslation();
  const dir = useDirection();
  const [status, setStatus] = useState<ScreenStatus>('loading');
  const [isEnrolled, setIsEnrolled] = useState(false);
  const [prefEnabled, setPrefEnabled] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  // Bootstrap: check enrollment + load preference
  useEffect(() => {
    (async () => {
      try {
        const [enrolled, pref] = await Promise.all([
          biometricLockService.isEnrolled(),
          biometricLockService.loadPreference(),
        ]);
        setIsEnrolled(enrolled);
        setPrefEnabled(pref && enrolled);
        setStatus('data');
      } catch (err) {
        console.error('[BiometricSettingsScreen] Load failed:', err);
        setStatus('error');
      }
    })();
  }, []);

  const handleToggle = async (newValue: boolean) => {
    if (!isEnrolled) {
      // Should not be possible if toggle is disabled, but guard anyway
      return;
    }

    setIsSaving(true);
    try {
      await biometricLockService.savePreference(newValue);
      setPrefEnabled(newValue);
    } catch (err) {
      console.error('[BiometricSettingsScreen] Toggle failed:', err);
      setStatus('error');
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <AsyncScreen status={status} testID="settings-biometric">
      <ScrollView
        className="flex-1 bg-background"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingVertical: 16 }}
      >
        {/* Device Status Section */}
        <View className="mb-6 px-4">
          <Text
            className="text-xs font-semibold text-muted-foreground uppercase tracking-wider pb-2"
            style={{ textAlign: dir.textAlign }}
          >
            {t('biometric.status', 'Device Status')}
          </Text>
          <View className="rounded-xl border border-border bg-card p-4">
            <Text className="text-base text-foreground">
              {isEnrolled
                ? t('biometric.deviceSupported', 'Face ID / Fingerprint Available')
                : t('biometric.deviceUnsupported', 'No Biometric Available')}
            </Text>
            {!isEnrolled && (
              <Text className="text-sm text-muted-foreground mt-2">
                {t(
                  'biometric.deviceUnsupportedExplain',
                  'Your device does not have biometric authentication enrolled. Please enroll Face ID or fingerprint in device settings to use this feature.',
                )}
              </Text>
            )}
          </View>
        </View>

        {/* Enable/Disable Toggle */}
        <View className="mb-6 px-4">
          <Text
            className="text-xs font-semibold text-muted-foreground uppercase tracking-wider pb-2"
            style={{ textAlign: dir.textAlign }}
          >
            {t('biometric.settings', 'Lock Settings')}
          </Text>
          <View className="rounded-xl border border-border bg-card overflow-hidden">
            <View
              className="flex-row items-center justify-between px-4 py-4"
              style={{ flexDirection: dir.flexRow }}
            >
              <View className="flex-1" style={{ marginStart: dir.isRTL ? 8 : 0 }}>
                <Text className="text-base font-semibold text-foreground">
                  {t('biometric.requireOnOpen', 'Require on App Open')}
                </Text>
                <Text className="text-sm text-muted-foreground mt-1">
                  {t(
                    'biometric.requireOnOpenHint',
                    'Authenticate every time you open the app',
                  )}
                </Text>
              </View>

              {isSaving ? (
                <ActivityIndicator size="small" color="#6C3CE1" />
              ) : (
                <Switch
                  value={prefEnabled && isEnrolled}
                  onValueChange={handleToggle}
                  disabled={!isEnrolled || isSaving}
                  accessibilityLabel={t(
                    'biometric.requireOnOpenToggle',
                    'Require biometric on app open',
                  )}
                  accessibilityRole="switch"
                  accessibilityState={{ checked: prefEnabled && isEnrolled }}
                />
              )}
            </View>
          </View>
        </View>

        {/* Info Section */}
        <View className="px-4">
          <Text
            className="text-xs font-semibold text-muted-foreground uppercase tracking-wider pb-2"
            style={{ textAlign: dir.textAlign }}
          >
            {t('biometric.about', 'About')}
          </Text>
          <View className="rounded-xl border border-border bg-card p-4">
            <Text className="text-sm text-muted-foreground leading-6">
              {t(
                'biometric.aboutText',
                'When enabled, you will be asked to authenticate with Face ID or fingerprint when you open the app. This protects your conversations and memories from unauthorized access.',
              )}
            </Text>
          </View>
        </View>
      </ScrollView>
    </AsyncScreen>
  );
}
