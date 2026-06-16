import { match } from '@formatjs/intl-localematcher';
import enMessages from './locales/en.json';
export const SUPPORTED_LOCALES = ['en']; // expand in v1.2.0: de, es, fr, pt-BR, it, ja, pl
export const DEFAULT_LOCALE = 'en';
export const RTL_LOCALES = ['ar', 'he', 'fa', 'ur'];
export function detectLocale() {
    const browserLocales = navigator.languages || [navigator.language];
    return match(browserLocales, SUPPORTED_LOCALES, DEFAULT_LOCALE);
}
export function isRTL(locale) {
    return RTL_LOCALES.includes(locale);
}
export const MESSAGES = {
    en: enMessages,
};
