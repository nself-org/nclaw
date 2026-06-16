/**
 * Purpose: ɳClaw desktop root component. Wraps the app with shared providers and
 *          renders the main shell. Auth state drives the top-level view.
 * Inputs:  Auth context from NselfAuthProvider (via useAuth hook).
 * Outputs: Renders i18n-wrapped shell. Unauthenticated state shows a sign-in prompt.
 * Constraints:
 *   - NselfI18nProvider wraps all children so useNselfTranslation() works everywhere.
 *   - Do NOT lift graphql queries here — let page components own their queries.
 *   - RTL: document.documentElement.dir is set on locale change via i18next languageChanged event.
 * SPORT: F08-SERVICE-INVENTORY.md — nclaw-desktop-app-shell
 */

import React from 'react';
import * as Sentry from '@sentry/react';
import { NselfI18nProvider, isRTL, useNselfTranslation, useTranslation } from '@nself/i18n';
import { useAuth } from '@nself/auth-core';
import { initObservability } from '@nself/observability';

// Initialize Sentry error reporting (runs at module load, before first render)
if (process.env.REACT_APP_SENTRY_DSN) {
  initObservability({
    sentry: {
      sdk: Sentry as any, // Web SDK has different signature; type coercion needed
      dsn: process.env.REACT_APP_SENTRY_DSN,
      environment: process.env.NODE_ENV ?? 'development',
      appKind: 'web' as const,
      release: process.env.REACT_APP_VERSION ?? '1.1.5',
      tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1.0,
    },
  });
}

// ─── RTL hook — sets document dir on locale change (Tauri embeds Vite SPA) ───

function useDocumentDir(): void {
  const { i18n } = useTranslation();
  React.useEffect(() => {
    const applyDir = (lang: string): void => {
      document.documentElement.dir = isRTL(lang) ? 'rtl' : 'ltr';
    };
    // Apply immediately for current language
    applyDir(i18n.language ?? 'en');
    // Keep in sync when locale changes at runtime
    i18n.on('languageChanged', applyDir);
    return () => {
      i18n.off('languageChanged', applyDir);
    };
  }, [i18n]);
}

// ─── Inner shell (inside auth context) ───────────────────────────────────────

function Shell(): React.ReactElement {
  const { status } = useAuth();
  const { t } = useNselfTranslation();
  useDocumentDir();

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        height: '100vh',
        fontFamily: 'system-ui, sans-serif',
        backgroundColor: '#030712',
        color: '#f9fafb',
      }}
    >
      <h1 style={{ fontSize: '2.5rem', margin: 0 }}>{t('desktop.nclaw.title')}</h1>
      <div style={{ marginTop: '0.5rem', color: '#6b7280', fontSize: '0.875rem' }}>
        {t('desktop.nclaw.version')}
      </div>
      {status === 'loading' && (
        <div style={{ marginTop: '1rem', color: '#6b7280', fontSize: '0.75rem' }}>
          {t('desktop.nclaw.loading')}
        </div>
      )}
      {status === 'unauthenticated' && (
        <div style={{ marginTop: '1rem', color: '#6b7280', fontSize: '0.75rem' }}>
          {t('desktop.nclaw.signInPrompt')}
        </div>
      )}
    </div>
  );
}

// ─── Root component ───────────────────────────────────────────────────────────

function App(): React.ReactElement {
  return (
    <Sentry.ErrorBoundary fallback={<div>An error occurred</div>}>
      <NselfI18nProvider>
        <Sentry.Profiler name="AppShell">
          <Shell />
        </Sentry.Profiler>
      </NselfI18nProvider>
    </Sentry.ErrorBoundary>
  );
}

export default Sentry.withProfiler(App);
