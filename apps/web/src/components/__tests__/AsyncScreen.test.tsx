/**
 * Tests for components/ui/AsyncScreen.tsx — 7-state data surface wrapper.
 *
 * Coverage:
 *   - State 1: loading=true renders skeleton (not populated content)
 *   - State 2: offline=true renders offline content
 *   - State 3: error (generic) renders error card with retry button
 *   - State 4: error with 429 status renders rate-limited content
 *   - State 5: error with 401 status renders permission-denied content
 *   - State 6: empty=true renders empty content
 *   - State 7: all false/no-error renders populated children
 *   - State priority: loading > offline > error > rate-limited > permission-denied > empty > populated
 *   - Custom skeleton slot is rendered during loading
 *   - Custom emptyContent slot is rendered when empty
 *   - onRetry callback is called when Retry button clicked
 *   - Rate-limit countdown renders and shows seconds
 *   - Permission-denied shows sign-in CTA
 */

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';
import { AsyncScreen } from '../ui/AsyncScreen';

// ─── Helper ──────────────────────────────────────────────────────────────────

function makeError(status: number, message = 'Error'): Error & { status: number } {
  return Object.assign(new Error(message), { status });
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('AsyncScreen — 7 UI states', () => {
  const POPULATED_TEXT = 'Populated content';
  const SKELETON_TEXT = 'Custom skeleton';
  const EMPTY_TEXT = 'Custom empty CTA';

  function renderScreen(
    overrides: Partial<React.ComponentProps<typeof AsyncScreen>> = {},
  ) {
    const defaults: React.ComponentProps<typeof AsyncScreen> = {
      loading: false,
      empty: false,
      error: undefined,
      offline: false,
      permissionDenied: false,
      rateLimited: false,
      skeleton: <div>{SKELETON_TEXT}</div>,
      emptyContent: <div>{EMPTY_TEXT}</div>,
      children: <div data-testid="populated">{POPULATED_TEXT}</div>,
    };
    return render(<AsyncScreen {...defaults} {...overrides} />);
  }

  // ── State 1: loading ──────────────────────────────────────────────────────

  it('State 1 — loading: renders skeleton, hides populated content', () => {
    renderScreen({ loading: true });
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
    expect(screen.getByText(SKELETON_TEXT)).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  it('State 1 — loading: uses default skeleton when skeleton prop is omitted', () => {
    renderScreen({ loading: true, skeleton: undefined });
    expect(screen.getByRole('status', { name: /loading/i })).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  // ── State 2: offline ──────────────────────────────────────────────────────

  it('State 2 — offline: renders offline content', () => {
    renderScreen({ offline: true });
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  it('State 2 — offline takes priority over error', () => {
    renderScreen({ offline: true, error: new Error('should not show') });
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-error')).toBeNull();
  });

  // ── State 3: generic error ────────────────────────────────────────────────

  it('State 3 — error: renders error card with message', () => {
    renderScreen({ error: new Error('Network failure') });
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
    expect(screen.getByText(/Network failure/)).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  it('State 3 — error: Retry button calls onRetry', () => {
    const onRetry = vi.fn();
    renderScreen({ error: new Error('Oops'), onRetry });
    fireEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it('State 3 — error: no Retry button when onRetry is absent', () => {
    renderScreen({ error: new Error('Silent fail') });
    expect(screen.queryByRole('button', { name: /retry/i })).toBeNull();
  });

  // ── State 4: rate-limited (429) ───────────────────────────────────────────

  it('State 4 — rate-limited: renders countdown when rateLimited=true', () => {
    renderScreen({ rateLimited: true, retryAfter: 30 });
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  it('State 4 — rate-limited: auto-detected from 429 error status', () => {
    renderScreen({ error: makeError(429) });
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-error')).toBeNull();
  });

  it('State 4 — rate-limited: countdown value is rendered', () => {
    renderScreen({ rateLimited: true, retryAfter: 30 });
    expect(screen.getByTestId('rate-limit-countdown')).toBeTruthy();
    expect(screen.getByTestId('rate-limit-countdown').textContent).toBe('30');
  });

  // ── State 5: permission-denied (401/403) ──────────────────────────────────

  it('State 5 — permission-denied: renders lock content when permissionDenied=true', () => {
    renderScreen({ permissionDenied: true });
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  it('State 5 — permission-denied: auto-detected from 401 error status', () => {
    renderScreen({ error: makeError(401) });
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-error')).toBeNull();
  });

  it('State 5 — permission-denied: auto-detected from 403 error status', () => {
    renderScreen({ error: makeError(403) });
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 5 — permission-denied: shows sign-in button', () => {
    renderScreen({ permissionDenied: true });
    expect(screen.getByRole('button', { name: /sign in again/i })).toBeTruthy();
  });

  // ── State 6: empty ────────────────────────────────────────────────────────

  it('State 6 — empty: renders emptyContent slot', () => {
    renderScreen({ empty: true });
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(EMPTY_TEXT)).toBeTruthy();
    expect(screen.queryByTestId('populated')).toBeNull();
  });

  it('State 6 — empty: uses default empty when emptyContent prop is omitted', () => {
    renderScreen({ empty: true, emptyContent: undefined });
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
  });

  // ── State 7: populated ────────────────────────────────────────────────────

  it('State 7 — populated: renders children when all states are false/no-error', () => {
    renderScreen();
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
    expect(screen.getByText(POPULATED_TEXT)).toBeTruthy();
  });

  // ── Priority ordering ─────────────────────────────────────────────────────

  it('Priority: loading wins over offline', () => {
    renderScreen({ loading: true, offline: true });
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-offline')).toBeNull();
  });

  it('Priority: loading wins over error', () => {
    renderScreen({ loading: true, error: new Error('x') });
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-error')).toBeNull();
  });

  it('Priority: loading wins over empty', () => {
    renderScreen({ loading: true, empty: true });
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-empty')).toBeNull();
  });

  it('Priority: offline wins over error (non-status error)', () => {
    renderScreen({ offline: true, error: new Error('Net') });
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('Priority: rate-limited wins over empty', () => {
    renderScreen({ rateLimited: true, empty: true });
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-empty')).toBeNull();
  });

  it('Priority: permission-denied wins over empty', () => {
    renderScreen({ permissionDenied: true, empty: true });
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
    expect(screen.queryByTestId('async-screen-empty')).toBeNull();
  });
});
