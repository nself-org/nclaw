/**
 * i18n Configuration — nclaw mobile (React Native + Expo)
 *
 * Purpose: Initialize i18next with locale detection via expo-localization and RTL support.
 * Exports: initializeI18n() function and locale hook for use in app root.
 *
 * Inputs: none (reads device locale via expo-localization)
 * Outputs: Initialized i18next instance with all 8 locales
 * Constraints: Must be called before rendering app root
 *
 * SPORT: None — updated in T09
 */

import { I18nManager } from 'react-native'
import * as Localization from 'expo-localization'
import { initializeI18next } from '@nself/i18n'

/**
 * Get device locale fallback to English.
 * expo-localization.getLocales()[0]?.languageCode returns BCP47 tag like 'ar', 'en', 'zh', etc.
 */
export const getDeviceLocale = (): string => {
  const deviceLocales = Localization.getLocales()
  if (deviceLocales.length > 0) {
    const localeCode = deviceLocales[0]?.languageCode || 'en'
    // Map common language codes to our supported locales
    // expo returns 'en', 'ar', 'zh', etc. which match our i18n Locale type
    return localeCode
  }
  return 'en'
}

/**
 * Initialize i18n for mobile app.
 * - Detects device locale via expo-localization
 * - Enables RTL layout for Arabic (I18nManager.forceRTL)
 * - Falls back to English if locale not supported
 *
 * Must be called in app root before rendering UI.
 */
export const initializeI18n = (overrideLocale?: string): void => {
  const deviceLocale = overrideLocale || getDeviceLocale()
  const supportedLocales = ['en', 'fr', 'ar', 'es', 'zh', 'ja', 'de', 'pt']
  const locale = supportedLocales.includes(deviceLocale) ? deviceLocale : 'en'

  // Initialize i18next with the detected locale
  initializeI18next(locale as any)

  // Enable RTL layout for Arabic
  if (locale === 'ar') {
    I18nManager.forceRTL(true)
  } else {
    I18nManager.forceRTL(false)
  }
}

