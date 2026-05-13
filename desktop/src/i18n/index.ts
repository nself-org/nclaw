import { match } from '@formatjs/intl-localematcher';
import enMessages from './locales/en.json';

export const SUPPORTED_LOCALES = ['en'] as const;  // expand in v1.2.0: de, es, fr, pt-BR, it, ja, pl
export const DEFAULT_LOCALE = 'en';
export const RTL_LOCALES = ['ar', 'he', 'fa', 'ur'] as const;

export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

export function detectLocale(): SupportedLocale {
  const browserLocales = navigator.languages || [navigator.language];
  return match(browserLocales as string[], SUPPORTED_LOCALES as unknown as string[], DEFAULT_LOCALE) as SupportedLocale;
}

export function isRTL(locale: SupportedLocale): boolean {
  return (RTL_LOCALES as ReadonlyArray<string>).includes(locale);
}

export const MESSAGES: Record<SupportedLocale, Record<string, string>> = {
  en: enMessages as Record<string, string>,
};
