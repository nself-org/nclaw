/**
 * Purpose: Initialize Sentry error tracking and performance monitoring.
 * Inputs:  VITE_SENTRY_DSN environment variable (optional; disabled if not set)
 * Outputs: Initialized Sentry SDK configured with browser tracing and ErrorBoundary support
 * Constraints: Only initializes if DSN is provided. Never hardcode DSN.
 *              tracesSampleRate set to 0.1 (10% sampling for perf) to avoid quota issues.
 * SPORT: T-P3-E5-W1-S1-T05 — Sentry instrumentation
 */

import * as Sentry from '@sentry/react';

/**
 * Initialize Sentry for error tracking and performance monitoring.
 * Call this in the root app provider or layout, before rendering any components.
 */
export function initializeSentry(): void {
  const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

  if (!dsn) {
    console.debug('Sentry DSN not provided — error tracking disabled');
    return;
  }

  try {
    Sentry.init({
      dsn,
      integrations: [
        // v8 browser tracing — routing instrumentation is auto-wired by the integration.
        Sentry.browserTracingIntegration(),
      ],
      // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
      // We recommend adjusting this value in production to avoid quota issues.
      // Default 0.1 captures 10% of transactions, suitable for production.
      tracesSampleRate: 0.1,
      // Capture breadcrumbs for user actions
      maxBreadcrumbs: 50,
      // Automatically capture exceptions
      attachStacktrace: true,
    });
  } catch (error) {
    console.error('Failed to initialize Sentry:', error);
  }
}

/**
 * Capture an exception in Sentry.
 * Use in error boundaries or try-catch blocks.
 */
export function captureException(error: Error, context?: Record<string, unknown>): void {
  if (context) {
    Sentry.captureException(error, {
      contexts: { extra: context },
    });
  } else {
    Sentry.captureException(error);
  }
}

/**
 * Capture a message in Sentry for logging important events.
 */
export function captureMessage(message: string, level: 'info' | 'warning' | 'error' = 'info'): void {
  Sentry.captureMessage(message, level);
}
