/**
 * Purpose: ɳClaw desktop root component. Wraps the app with shared providers and
 *          renders the main shell. Auth state drives the top-level view.
 * Inputs:  Auth context from NselfAuthProvider (via useAuth hook).
 * Outputs: Renders i18n-wrapped shell. Unauthenticated state shows a sign-in prompt.
 * Constraints:
 *   - NselfI18nProvider wraps all children so useNselfTranslation() works everywhere.
 *   - Do NOT lift graphql queries here — let page components own their queries.
 * SPORT: F08-SERVICE-INVENTORY.md — nclaw-desktop-app-shell
 */

import React from 'react';
import { NselfI18nProvider } from '@nself/i18n';
import { useAuth } from '@nself/auth-core';

// ─── Inner shell (inside auth context) ───────────────────────────────────────

function Shell(): React.ReactElement {
  const { status } = useAuth();

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
      <h1 style={{ fontSize: '2.5rem', margin: 0 }}>ɳClaw</h1>
      <div style={{ marginTop: '0.5rem', color: '#6b7280', fontSize: '0.875rem' }}>
        v1.1.1
      </div>
      {status === 'loading' && (
        <div style={{ marginTop: '1rem', color: '#6b7280', fontSize: '0.75rem' }}>
          Loading…
        </div>
      )}
      {status === 'unauthenticated' && (
        <div style={{ marginTop: '1rem', color: '#6b7280', fontSize: '0.75rem' }}>
          Sign in to get started
        </div>
      )}
    </div>
  );
}

// ─── Root component ───────────────────────────────────────────────────────────

function App(): React.ReactElement {
  return (
    <NselfI18nProvider>
      <Shell />
    </NselfI18nProvider>
  );
}

export default App;
