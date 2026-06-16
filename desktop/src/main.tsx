/**
 * Purpose: ɳClaw desktop entry point — initialises observability, auth, i18n, and GraphQL
 *          before mounting the React tree. Tauri 2 provides the native shell.
 * Inputs:  VITE_NSELF_SENTRY_DSN, VITE_APP_ENV, VITE_APP_VERSION from build env.
 * Outputs: React app mounted on #root, Sentry + OTel registered, i18next initialised.
 * Constraints:
 *   - initObservability() MUST be called before ReactDOM.createRoot() so Sentry catches
 *     any errors thrown during React hydration.
 *   - initializeI18next() runs synchronously at module level — must complete before render.
 *   - NselfAuthProvider wraps the whole tree so useAuth() works in all components.
 *   - authStrategy and graphqlClient singletons are created in their own modules to avoid
 *     circular imports; they are stable references (never recreated).
 * SPORT: F08-SERVICE-INVENTORY.md — nclaw-desktop-main
 */

import * as Sentry from '@sentry/react';
import type { SentrySdk } from '@nself/observability';
import { initObservability } from '@nself/observability';
import { NselfAuthProvider } from '@nself/auth-core';
import { initializeI18next } from '@nself/i18n';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { Provider as UrqlProvider } from 'urql';
import App from './App';
import { authStrategy } from './lib/auth';
import { graphqlClient } from './lib/graphql';

// ─── i18n init (module level — before first render) ──────────────────────────
initializeI18next();

// ─── Sentry + OTel init (before React mounts) ────────────────────────────────
initObservability({
  sentry: {
    sdk: Sentry as unknown as SentrySdk,
    dsn: import.meta.env.VITE_NSELF_SENTRY_DSN ?? '',
    environment: import.meta.env.VITE_APP_ENV ?? 'development',
    appKind: 'native',
    tracesSampleRate: import.meta.env.VITE_APP_ENV === 'production' ? 0.2 : 1.0,
    release: import.meta.env.VITE_APP_VERSION ?? '1.1.5',
  },
});

// ─── React tree ───────────────────────────────────────────────────────────────
ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <NselfAuthProvider strategy={authStrategy}>
      <UrqlProvider value={graphqlClient}>
        <App />
      </UrqlProvider>
    </NselfAuthProvider>
  </React.StrictMode>,
);
