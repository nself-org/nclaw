import { IntlProvider } from 'react-intl';
import { useState, ReactNode } from 'react';
import { detectLocale, MESSAGES, type SupportedLocale } from '@/i18n';

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale] = useState<SupportedLocale>(detectLocale());
  return (
    <IntlProvider locale={locale} messages={MESSAGES[locale]} defaultLocale="en">
      {children}
    </IntlProvider>
  );
}
