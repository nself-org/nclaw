'use client';

/**
 * useNetworkStatus — reactive network connectivity hook.
 *
 * Purpose: Wraps navigator.onLine and window offline/online events to provide
 *          a reactive boolean that updates when the device goes offline or online.
 *          Used by AsyncScreen and all data-fetching pages to gate mutations
 *          and surface OfflineBanner when disconnected.
 *
 * Inputs: none
 * Outputs: { isOnline: boolean }
 * Constraints:
 *   - SSR-safe: navigator is not available server-side; defaults to true.
 *   - Updates synchronously on event; no polling or debounce needed.
 *
 * SOT: T-P3-E5-W1-S1-T01-a
 */

import { useEffect, useState } from 'react';

interface NetworkStatus {
  isOnline: boolean;
}

export function useNetworkStatus(): NetworkStatus {
  const [isOnline, setIsOnline] = useState<boolean>(() => {
    // SSR guard: navigator is undefined on the server
    if (typeof navigator === 'undefined') return true;
    return navigator.onLine;
  });

  useEffect(() => {
    function handleOnline(): void {
      setIsOnline(true);
    }

    function handleOffline(): void {
      setIsOnline(false);
    }

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    // Sync on mount in case the state changed between render and effect
    setIsOnline(navigator.onLine);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return { isOnline };
}
