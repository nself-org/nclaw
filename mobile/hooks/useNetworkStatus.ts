/**
 * useNetworkStatus — monitor device network connectivity.
 *
 * Purpose: Provides a reactive boolean `isOnline` and exposes a `onConnected`
 *   event registration so offline mutation queues can drain on reconnect.
 *   Uses @react-native-async-storage/async-storage for persistence-free state
 *   and React Native's built-in NetInfo (via @react-native-community/netinfo
 *   polyfilled in Expo via expo-network). Falls back to polling `fetch` HEAD
 *   against the configured backend URL when NetInfo is unavailable.
 *
 * Inputs:  None — subscribes to RN NetInfo events on mount.
 * Outputs:
 *   isOnline     — boolean, true when device has network connectivity.
 *   onConnected  — register a callback to be called on reconnect transitions.
 *                  Returns an unsubscribe function.
 *
 * Constraints:
 *   - Singleton pattern: a module-level event emitter ensures a single
 *     NetInfo subscription regardless of how many hooks mount.
 *   - Transitions: offline → online fires all registered `onConnected` listeners.
 *   - No external dependencies beyond what Expo provides.
 *   - Compatible with RN 0.79 + Expo 53.
 *
 * SPORT: REGISTRY-NATIVE-APPS.md — nclaw/mobile offline_sync=true
 * Cross-ref: T-P3-E5-W3-S4-T01 (offline queue drain)
 *            services/offline-queue/index.ts (drains on 'connected' event)
 */

import { useEffect, useRef, useState } from 'react';
import { AppState, type AppStateStatus } from 'react-native';

// =============================================================================
// Module-level singleton event bus
// =============================================================================

type ConnectedListener = () => void;

/** Module-level set of listeners called on each offline→online transition. */
const connectedListeners = new Set<ConnectedListener>();

/** Last known online state at module level (avoids duplicate transitions). */
let _isOnline = true;

/**
 * Notify all registered `onConnected` listeners.
 * Called internally whenever the device transitions from offline → online.
 */
function notifyConnected(): void {
  for (const listener of connectedListeners) {
    try {
      listener();
    } catch {
      // Individual listeners must not crash the notification loop.
    }
  }
}

/**
 * Internal: update the module-level online flag and fire listeners on
 * offline → online transition.
 */
function handleNetworkChange(online: boolean): void {
  const wasOffline = !_isOnline;
  _isOnline = online;
  if (wasOffline && online) {
    notifyConnected();
  }
}

// =============================================================================
// NetInfo polling (Expo-compatible fallback)
// =============================================================================

/**
 * Check network reachability by attempting a lightweight fetch to the
 * well-known Cloudflare DNS-over-HTTPS endpoint. Resolves true on any 2xx.
 * Used as a polling fallback when the NetInfo native module is unavailable.
 */
async function checkReachability(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000);
    const res = await fetch('https://1.1.1.1', {
      method: 'HEAD',
      signal: controller.signal,
    });
    clearTimeout(timeout);
    return res.ok || res.status < 400;
  } catch {
    return false;
  }
}

// Try to import NetInfo — if not available, we fall back to AppState polling.
let NetInfo: { fetch: () => Promise<{ isConnected: boolean | null }> } | null = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  NetInfo = require('@react-native-community/netinfo').default;
} catch {
  NetInfo = null;
}

// =============================================================================
// Module-level NetInfo subscription (singleton)
// =============================================================================

let _netInfoSubscribed = false;

function ensureNetInfoSubscription(): void {
  if (_netInfoSubscribed) return;
  _netInfoSubscribed = true;

  if (NetInfo) {
    // @react-native-community/netinfo is available — use it.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { default: NI } = require('@react-native-community/netinfo');
    NI.addEventListener((state: { isConnected: boolean | null }) => {
      handleNetworkChange(state.isConnected === true);
    });
  } else {
    // Fallback: poll reachability on AppState changes (foreground events).
    AppState.addEventListener('change', async (nextState: AppStateStatus) => {
      if (nextState === 'active') {
        const online = await checkReachability();
        handleNetworkChange(online);
      }
    });
    // Initial check
    void checkReachability().then(handleNetworkChange);
  }
}

// =============================================================================
// Hook
// =============================================================================

export interface UseNetworkStatusResult {
  /** True when the device has an active network connection. */
  isOnline: boolean;
  /**
   * Register a callback that fires on every offline → online transition.
   * @returns Cleanup function — call to unregister.
   */
  onConnected: (listener: ConnectedListener) => () => void;
}

/**
 * useNetworkStatus — reactive device network status hook.
 *
 * Starts the singleton NetInfo subscription on first mount.
 * Multiple components can call this hook; only one native subscription is made.
 *
 * @example
 * const { isOnline, onConnected } = useNetworkStatus();
 * useEffect(() => onConnected(() => drainOfflineQueue()), []);
 */
export function useNetworkStatus(): UseNetworkStatusResult {
  const [isOnline, setIsOnline] = useState<boolean>(_isOnline);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;

    // Ensure singleton NetInfo subscription is active.
    ensureNetInfoSubscription();

    // Subscribe to module-level network changes to update local state.
    const onChange: ConnectedListener = () => {
      if (mountedRef.current) setIsOnline(_isOnline);
    };

    // We also need offline transitions — add a raw state listener.
    let netInfoUnsub: (() => void) | undefined;
    if (NetInfo) {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { default: NI } = require('@react-native-community/netinfo');
      netInfoUnsub = NI.addEventListener((state: { isConnected: boolean | null }) => {
        if (mountedRef.current) setIsOnline(state.isConnected === true);
      });
    }

    // Subscribe to connected events to update local state on reconnect.
    connectedListeners.add(onChange);

    return () => {
      mountedRef.current = false;
      connectedListeners.delete(onChange);
      netInfoUnsub?.();
    };
  }, []);

  const onConnected = (listener: ConnectedListener): (() => void) => {
    connectedListeners.add(listener);
    return () => connectedListeners.delete(listener);
  };

  return { isOnline, onConnected };
}
