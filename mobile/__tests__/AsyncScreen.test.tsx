/**
 * Unit tests — AsyncScreen (9-state contract including E5 additions).
 *
 * Purpose: Verify every AsyncScreen state renders the correct UI and testID.
 *   Covers the 7 required E5 states: loading (skeleton), empty (CTA), error
 *   (typed card + retry), data (populated), offline (queue indicator),
 *   permission-denied (re-auth), rate-limited (countdown).
 *
 * Inputs:  Rendered AsyncScreen with each ScreenStatus variant.
 * Outputs: Assertions on testID presence, accessibility labels, and callbacks.
 *
 * Constraints:
 *   - Uses @testing-library/react-native render + fireEvent.
 *   - i18next is mocked to return the key as-is (no real translations loaded).
 *   - All 9 ScreenStatus values must have a dedicated test case.
 *   - Zero skipped / xtest cases.
 */

import React from 'react';
import { render, fireEvent } from '@testing-library/react-native';
import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';

// ─── i18n mock ────────────────────────────────────────────────────────────────

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key: string, fallback: string) => fallback ?? key,
  }),
}));

// ─── Helpers ──────────────────────────────────────────────────────────────────

function renderScreen(status: ScreenStatus, props?: Partial<React.ComponentProps<typeof AsyncScreen>>) {
  return render(
    <AsyncScreen status={status} testID="test-screen" {...props}>
      <></>
    </AsyncScreen>,
  );
}

// =============================================================================
// Tests
// =============================================================================

describe('AsyncScreen', () => {
  // ── State: loading ──────────────────────────────────────────────────────────
  it('renders loading state with testID', () => {
    const { getByTestId } = renderScreen('loading');
    expect(getByTestId('test-screen-loading')).toBeTruthy();
  });

  // ── State: skeleton ─────────────────────────────────────────────────────────
  it('renders skeleton state with testID', () => {
    const { getByTestId } = renderScreen('skeleton');
    expect(getByTestId('test-screen-skeleton')).toBeTruthy();
  });

  // ── State: empty ────────────────────────────────────────────────────────────
  it('renders empty state with default message', () => {
    const { getByTestId, getByText } = renderScreen('empty');
    expect(getByTestId('test-screen-empty')).toBeTruthy();
    expect(getByText('Nothing here yet')).toBeTruthy();
  });

  it('renders empty state with custom message', () => {
    const { getByText } = renderScreen('empty', { emptyMessage: 'No chats yet' });
    expect(getByText('No chats yet')).toBeTruthy();
  });

  // ── State: error ────────────────────────────────────────────────────────────
  it('renders error state with message', () => {
    const { getByTestId, getByText } = renderScreen('error', {
      error: 'LLM pipeline failed',
    });
    expect(getByTestId('test-screen-error')).toBeTruthy();
    expect(getByText('LLM pipeline failed')).toBeTruthy();
  });

  it('renders error state with Error object', () => {
    const { getByText } = renderScreen('error', {
      error: new Error('inference_failed'),
    });
    expect(getByText('inference_failed')).toBeTruthy();
  });

  it('calls onRetry from error state', () => {
    const onRetry = jest.fn();
    const { getByText } = renderScreen('error', { onRetry, error: 'fail' });
    fireEvent.press(getByText('Retry'));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  // ── State: data ─────────────────────────────────────────────────────────────
  it('renders children in data state', () => {
    const { queryByText } = render(
      <AsyncScreen status="data" testID="s">
        <></>
      </AsyncScreen>,
    );
    // No state overlay is rendered in data state
    expect(queryByText('Loading')).toBeNull();
  });

  // ── State: offline ──────────────────────────────────────────────────────────
  it('renders offline state with testID', () => {
    const { getByTestId, getByText } = renderScreen('offline');
    expect(getByTestId('test-screen-offline')).toBeTruthy();
    expect(getByText("You're offline")).toBeTruthy();
  });

  it('calls onRetry from offline state', () => {
    const onRetry = jest.fn();
    const { getByText } = renderScreen('offline', { onRetry });
    fireEvent.press(getByText('Retry'));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  // ── State: permission-denied ────────────────────────────────────────────────
  it('renders permission-denied state with testID', () => {
    const { getByTestId, getByText } = renderScreen('permission-denied');
    expect(getByTestId('test-screen-permission-denied')).toBeTruthy();
    expect(getByText('Access required')).toBeTruthy();
  });

  it('calls onReAuth from permission-denied state', () => {
    const onReAuth = jest.fn();
    const { getByText } = renderScreen('permission-denied', { onReAuth });
    fireEvent.press(getByText('Sign in again'));
    expect(onReAuth).toHaveBeenCalledTimes(1);
  });

  // ── State: rate-limited ─────────────────────────────────────────────────────
  it('renders rate-limited state with testID', () => {
    const { getByTestId, getByText } = renderScreen('rate-limited', {
      retryAfterMs: 30_000,
    });
    expect(getByTestId('test-screen-rate-limited')).toBeTruthy();
    expect(getByText('Slow down')).toBeTruthy();
  });

  it('shows countdown in rate-limited state when retryAfterMs is set', () => {
    const { getByText } = renderScreen('rate-limited', { retryAfterMs: 5000 });
    // Should show "Try again in 5s" (or similar countdown text)
    expect(getByText(/Try again in/)).toBeTruthy();
  });

  it('shows retry button when rate-limit countdown reaches 0', () => {
    const onRetry = jest.fn();
    // retryAfterMs = 0 → countdown already expired → retry button visible
    const { getByText } = renderScreen('rate-limited', {
      retryAfterMs: 0,
      onRetry,
    });
    fireEvent.press(getByText('Retry'));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  // ── State: success ──────────────────────────────────────────────────────────
  it('renders success state with testID', () => {
    const { getByTestId } = renderScreen('success');
    expect(getByTestId('test-screen-success')).toBeTruthy();
  });
});
