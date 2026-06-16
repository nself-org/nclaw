/**
 * Tests for components/ErrorBoundary.tsx.
 *
 * Coverage:
 *   - Renders children when no error is thrown.
 *   - Catches a render-time throw and renders ErrorCard (not blank screen).
 *   - ErrorCard contains "Reload" button and "Report" link.
 *   - onError callback is invoked with the caught Error.
 *   - Custom fallback prop is rendered instead of default ErrorCard.
 */

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from '../ErrorBoundary';

// Suppress React's "The above error occurred in..." console.error in tests.
beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
});

// A component that unconditionally throws during render.
function BombComponent(): React.ReactElement {
  throw new Error('test render bomb');
}

// A component that renders fine.
function SafeComponent(): React.ReactElement {
  return <div data-testid="safe">Safe content</div>;
}

describe('ErrorBoundary', () => {
  it('renders children when no error occurs', () => {
    render(
      <ErrorBoundary>
        <SafeComponent />
      </ErrorBoundary>
    );
    expect(screen.getByTestId('safe')).toBeInTheDocument();
  });

  it('catches a render error and shows ErrorCard — not blank', () => {
    render(
      <ErrorBoundary>
        <BombComponent />
      </ErrorBoundary>
    );

    // The page must NOT be blank — some error UI must be rendered.
    // ErrorCard renders a heading "Something went wrong" by default.
    expect(screen.getByRole('alert')).toBeInTheDocument();
    expect(screen.getByText(/something went wrong/i)).toBeInTheDocument();
  });

  it('renders a Reload button in the fallback', () => {
    render(
      <ErrorBoundary>
        <BombComponent />
      </ErrorBoundary>
    );

    const reloadBtn = screen.getByRole('button', { name: /reload/i });
    expect(reloadBtn).toBeInTheDocument();
  });

  it('renders a Report link in the fallback', () => {
    render(
      <ErrorBoundary>
        <BombComponent />
      </ErrorBoundary>
    );

    const reportLink = screen.getByRole('link', { name: /report/i });
    expect(reportLink).toBeInTheDocument();
  });

  it('calls onError callback with the caught error', () => {
    const onError = vi.fn();

    render(
      <ErrorBoundary onError={onError}>
        <BombComponent />
      </ErrorBoundary>
    );

    expect(onError).toHaveBeenCalledTimes(1);
    const [error] = onError.mock.calls[0] as [Error, React.ErrorInfo];
    expect(error.message).toBe('test render bomb');
  });

  it('renders custom fallback prop instead of ErrorCard when provided', () => {
    render(
      <ErrorBoundary fallback={<div data-testid="custom-fallback">Custom!</div>}>
        <BombComponent />
      </ErrorBoundary>
    );

    expect(screen.getByTestId('custom-fallback')).toBeInTheDocument();
    // Default ErrorCard heading should NOT be present when custom fallback given.
    expect(screen.queryByText(/something went wrong/i)).not.toBeInTheDocument();
  });

  it('shows the error message in the ErrorCard body', () => {
    render(
      <ErrorBoundary>
        <BombComponent />
      </ErrorBoundary>
    );

    expect(screen.getByText(/test render bomb/i)).toBeInTheDocument();
  });
});
