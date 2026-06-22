import { match } from "@formatjs/intl-localematcher";
import enMessages from "./locales/en.json";

/** BCP 47 locale codes supported by ɳClaw. Expand in v1.2.0: de, es, fr, pt-BR, it, ja, pl. */
export const SUPPORTED_LOCALES = ["en"] as const;

/** Fallback locale used when the detected browser locale is not in SUPPORTED_LOCALES. */
export const DEFAULT_LOCALE = "en";

/** Locale codes that require a right-to-left text direction. */
export const RTL_LOCALES = ["ar", "he", "fa", "ur"] as const;

/** Union type of all currently supported locale codes. */
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

/**
 * Detect the best matching locale from the browser's language preferences.
 *
 * Uses `@formatjs/intl-localematcher` BCP 47 negotiation against SUPPORTED_LOCALES.
 * Falls back to DEFAULT_LOCALE when no match is found.
 */
export function detectLocale(): SupportedLocale {
  const browserLocales = navigator.languages || [navigator.language];
  return match(
    browserLocales as string[],
    SUPPORTED_LOCALES as unknown as string[],
    DEFAULT_LOCALE,
  ) as SupportedLocale;
}

/** Returns true when `locale` is a right-to-left writing system. */
export function isRTL(locale: SupportedLocale): boolean {
  return (RTL_LOCALES as ReadonlyArray<string>).includes(locale);
}

/** Flat message map keyed by locale code. Populated at build time from locale JSON files. */
export const MESSAGES: Record<SupportedLocale, Record<string, string>> = {
  en: enMessages as Record<string, string>,
};
