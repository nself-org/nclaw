/**
 * Purpose: Settings stack navigator layout.
 *   Wraps all settings sub-screens in a Stack.
 * Inputs:  None.
 * Outputs: Stack navigator with settings screens.
 * Constraints: headerShown true here (settings is a push screen, not a tab).
 * SPORT: None — SPORT updated in T09.
 */

import { Stack } from 'expo-router';
import { useTranslation } from 'react-i18next';

export default function SettingsLayout() {
  const { t } = useTranslation();
  return (
    <Stack>
      <Stack.Screen
        name="index"
        options={{ title: t('settings.title', 'Settings') }}
      />
      <Stack.Screen
        name="profile"
        options={{ title: t('settings.profile', 'Profile') }}
      />
      <Stack.Screen
        name="notifications"
        options={{ title: t('settings.notifications', 'Notifications') }}
      />
      <Stack.Screen
        name="theme"
        options={{ title: t('settings.theme', 'Appearance') }}
      />
      <Stack.Screen
        name="data-export"
        options={{ title: t('settings.dataExport', 'Data Export') }}
      />
      <Stack.Screen
        name="biometric-settings"
        options={{ title: t('settings.biometrics', 'Biometric Auth') }}
      />
    </Stack>
  );
}
