/**
 * Purpose: Re-export NselfI18nProvider from @nself/i18n for backward-compat imports
 *          within this codebase. New code should import from @nself/i18n directly.
 * Inputs:  Same props as NselfI18nProvider (locale?, children).
 * Outputs: NselfI18nProvider component.
 * Constraints: This file exists for migration compatibility only — do not add logic here.
 *   The hand-rolled IntlProvider setup is replaced by @nself/i18n (react-i18next based).
 * SPORT: F08-SERVICE-INVENTORY.md — nclaw-desktop-i18n
 */

export { NselfI18nProvider as I18nProvider } from '@nself/i18n';
