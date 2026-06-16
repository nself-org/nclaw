'use client';

/**
 * OfflineBanner — non-blocking offline notification bar.
 *
 * Purpose: Displayed across all claw-web pages when the device has no network
 *          connectivity. Non-blocking (does not replace page content); appears
 *          as a sticky banner so the user can still read cached content while
 *          knowing mutations will fail.
 *
 * Inputs:
 *   - isOnline: boolean — when false, renders the banner; when true, renders nothing.
 * Outputs: A sticky top banner or null.
 * Constraints:
 *   - Always use alongside useNetworkStatus hook.
 *   - Must have role="status" and aria-live="polite" for accessibility.
 *
 * SOT: T-P3-E5-W1-S1-T01-a
 */

import React from 'react';
import { WifiOff } from 'lucide-react';

interface OfflineBannerProps {
  isOnline: boolean;
}

export function OfflineBanner({ isOnline }: OfflineBannerProps): React.ReactElement | null {
  if (isOnline) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      data-testid="offline-banner"
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '0.5rem',
        padding: '0.5rem 1rem',
        background: 'var(--color-warning, #92400e)',
        color: '#fff',
        fontSize: '0.875rem',
        fontWeight: 500,
        position: 'sticky',
        top: 0,
        zIndex: 100,
      }}
    >
      <WifiOff size={16} aria-hidden="true" />
      <span>You&apos;re offline — changes will resume when you reconnect.</span>
    </div>
  );
}
