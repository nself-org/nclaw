/**
 * ErrorBoundary — route-level React error boundary for claw-web.
 *
 * Purpose: Catch rendering errors in a component subtree and render a
 *          recovery fallback (ErrorCard) so no route can show a blank screen.
 *          Mirrors the @nself/ui ErrorBoundary contract but is self-contained
 *          for claw-web (no @nself/ui peer dependency installed here).
 *
 * Inputs:
 *   children — React subtree to protect.
 *   onError  — optional: called with (error, errorInfo) for logging/Sentry.
 *
 * Outputs: children on success; ErrorCard fallback on caught render error.
 *
 * Constraints:
 *   - Must be a class component (React restriction on getDerivedStateFromError).
 *   - Does NOT catch: async errors, event handler errors, server errors.
 *     Use Result<T,ClawError> from lib/result for those.
 *   - Reset by changing the `key` prop on the wrapping <ErrorBoundary>.
 *
 * Usage:
 *   <ErrorBoundary>
 *     <ChatRoute />
 *   </ErrorBoundary>
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */

'use client';

import React from 'react';

// ─── ErrorCard ────────────────────────────────────────────────────────────────

interface ErrorCardProps {
  /** Brief heading shown to the user. */
  title?: string;
  /** Extended message shown below the heading. */
  message?: string;
}

/**
 * ErrorCard — minimal error display with Reload and Report CTAs.
 * Self-contained: no external UI library required.
 */
function ErrorCard({ title, message }: ErrorCardProps): React.ReactElement {
  return (
    <div
      role="alert"
      aria-live="assertive"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '1rem',
        padding: '3rem 2rem',
        minHeight: '100%',
        textAlign: 'center',
        color: 'var(--color-text, #e2e8f0)',
        background: 'var(--color-bg, #0F0F1A)',
      }}
    >
      {/* Icon */}
      <div
        aria-hidden="true"
        style={{ fontSize: '2.5rem', lineHeight: 1 }}
      >
        ⚠️
      </div>

      {/* Heading */}
      <h2
        style={{
          margin: 0,
          fontSize: '1.25rem',
          fontWeight: 600,
          color: 'var(--color-text, #e2e8f0)',
        }}
      >
        {title ?? 'Something went wrong'}
      </h2>

      {/* Message */}
      {message && (
        <p
          style={{
            margin: 0,
            maxWidth: '40ch',
            fontSize: '0.875rem',
            color: 'var(--color-text-muted, #94a3b8)',
            lineHeight: 1.6,
          }}
        >
          {message}
        </p>
      )}

      {/* CTA row */}
      <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap', justifyContent: 'center' }}>
        <button
          type="button"
          onClick={() => window.location.reload()}
          style={{
            padding: '0.5rem 1.25rem',
            borderRadius: '0.375rem',
            border: 'none',
            background: 'var(--color-accent, #6366f1)',
            color: '#fff',
            fontWeight: 600,
            cursor: 'pointer',
            fontSize: '0.875rem',
          }}
        >
          Reload
        </button>
        <a
          href="mailto:support@nself.org?subject=ɳClaw%20error%20report"
          style={{
            padding: '0.5rem 1.25rem',
            borderRadius: '0.375rem',
            border: '1px solid var(--color-border, #334155)',
            color: 'var(--color-text-muted, #94a3b8)',
            fontWeight: 500,
            cursor: 'pointer',
            fontSize: '0.875rem',
            textDecoration: 'none',
            display: 'inline-flex',
            alignItems: 'center',
          }}
        >
          Report
        </a>
      </div>
    </div>
  );
}

// ─── ErrorBoundary ────────────────────────────────────────────────────────────

export interface ErrorBoundaryProps {
  children: React.ReactNode;
  /**
   * Optional error reporter. Wire to @nself/observability or Sentry in production.
   * Signature matches React's componentDidCatch.
   */
  onError?: (error: Error, info: React.ErrorInfo) => void;
  /**
   * Custom fallback. If omitted, renders ErrorCard with defaults.
   */
  fallback?: React.ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends React.Component<
  ErrorBoundaryProps,
  ErrorBoundaryState
> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, info: React.ErrorInfo): void {
    this.props.onError?.(error, info);
  }

  override render(): React.ReactNode {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;
      return (
        <ErrorCard
          message={
            this.state.error?.message ?? 'An unexpected error occurred.'
          }
        />
      );
    }
    return this.props.children;
  }
}

export { ErrorCard };
export default ErrorBoundary;
