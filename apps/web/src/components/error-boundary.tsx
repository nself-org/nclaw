/**
 * Purpose: Error boundary component that catches uncaught React errors and sends them to Sentry.
 * Inputs:  children component tree
 * Outputs: Either rendered children or error fallback UI with recovery options
 * Constraints: Must be client-side ('use client'). Wrap around entire app as outermost boundary.
 *              Call captureException on error to report to Sentry.
 * SPORT: T-P3-E5-W1-S1-T05 — Sentry error boundaries
 */

'use client';

import * as Sentry from '@sentry/react';
import type { ReactNode } from 'react';
import { useEffect, useState } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

interface ErrorBoundaryWrapperProps {
  children: ReactNode;
}

/**
 * Fallback UI shown when an error is caught by the boundary.
 */
function ErrorFallback({
  error,
  resetError,
}: {
  error: Error;
  resetError: () => void;
}): React.ReactElement {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '100vh',
        padding: '20px',
        background: 'linear-gradient(135deg, #0f0f1a 0%, #1a1a2e 100%)',
        color: '#fff',
        fontFamily: 'system-ui, -apple-system, sans-serif',
      }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          marginBottom: '24px',
          color: '#ff6b6b',
        }}
      >
        <AlertTriangle size={32} />
        <h1 style={{ margin: 0, fontSize: '24px', fontWeight: 600 }}>
          Something went wrong
        </h1>
      </div>

      <p
        style={{
          maxWidth: '500px',
          marginBottom: '24px',
          color: '#a0a0b0',
          textAlign: 'center',
          lineHeight: '1.5',
        }}
      >
        We've been notified about this issue and are working on a fix. Please try refreshing the
        page.
      </p>

      <details
        style={{
          maxWidth: '500px',
          marginBottom: '24px',
          padding: '12px',
          background: 'rgba(255, 255, 255, 0.05)',
          border: '1px solid rgba(255, 255, 255, 0.1)',
          borderRadius: '8px',
          color: '#a0a0b0',
          fontSize: '12px',
          cursor: 'pointer',
        }}
      >
        <summary style={{ cursor: 'pointer', fontWeight: 500 }}>Error Details</summary>
        <pre
          style={{
            overflow: 'auto',
            marginTop: '8px',
            padding: '8px',
            background: 'rgba(0, 0, 0, 0.3)',
            borderRadius: '4px',
            fontSize: '11px',
            lineHeight: '1.4',
          }}
        >
          {error.message}
          {error.stack && `\n\n${error.stack}`}
        </pre>
      </details>

      <button
        onClick={resetError}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          padding: '10px 20px',
          background: '#5b9cf5',
          color: '#fff',
          border: 'none',
          borderRadius: '8px',
          fontSize: '14px',
          fontWeight: 500,
          cursor: 'pointer',
          transition: 'background 0.2s',
        }}
        onMouseEnter={(e) => {
          (e.currentTarget as HTMLButtonElement).style.background = '#4a8bd4';
        }}
        onMouseLeave={(e) => {
          (e.currentTarget as HTMLButtonElement).style.background = '#5b9cf5';
        }}
      >
        <RefreshCw size={16} />
        Try Again
      </button>
    </div>
  );
}

/**
 * Sentry ErrorBoundary wrapper for the ɳClaw web app.
 * Catches uncaught errors and reports to Sentry.
 */
export function ErrorBoundaryWrapper({ children }: ErrorBoundaryWrapperProps) {
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    // Capture unhandled promise rejections
    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
      const err = event.reason instanceof Error ? event.reason : new Error(String(event.reason));
      Sentry.captureException(err);
      setError(err);
    };

    window.addEventListener('unhandledrejection', handleUnhandledRejection);
    return () => {
      window.removeEventListener('unhandledrejection', handleUnhandledRejection);
    };
  }, []);

  if (error) {
    return (
      <ErrorFallback
        error={error}
        resetError={() => {
          setError(null);
          window.location.reload();
        }}
      />
    );
  }

  return (
    <Sentry.ErrorBoundary fallback={({ error, resetError }: { error: Error; resetError: () => void }) =>
      <ErrorFallback error={error} resetError={resetError} />
    }>
      {children}
    </Sentry.ErrorBoundary>
  );
}
