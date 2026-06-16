/**
 * useAppLock — Hook managing app lock state via AppState listener + biometric service.
 *
 * Purpose: Subscribe to app foreground/background transitions and trigger biometric
 *   authentication when needed. Separate from useBiometricAuth for modularity:
 *   this hook focuses on the app lifecycle, not preference persistence.
 * Inputs: None (reads from biometricLockService).
 * Outputs: { isLocked, onUnlock, isBiometricAvailable }.
 * Constraints:
 *   - Must clean up AppState listener on unmount.
 *   - Should not assume biometrics are available on all devices.
 *   - Graceful fallback: if unlock fails, user stays locked (not auto-unlock on error).
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-app-lock
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState, AppStateStatus } from 'react-native';
import { biometricLockService } from '../services/biometricLockService';

export interface UseAppLockReturn {
  /** True if the lock screen should be visible. */
  isLocked: boolean;
  /** Callback to unlock (trigger authentication). */
  onUnlock: () => Promise<boolean>;
  /** Whether device supports biometrics. */
  isBiometricAvailable: boolean;
}

/**
 * useAppLock — Track app lock state based on AppState + preference.
 */
export function useAppLock(): UseAppLockReturn {
  const [isLocked, setIsLocked] = useState(false);
  const [isBiometricAvailable, setIsBiometricAvailable] = useState(false);
  const appStateRef = useRef<AppStateStatus>(AppState.currentState);
  const prefEnabledRef = useRef(false);

  // Bootstrap: check enrollment + load preference
  useEffect(() => {
    (async () => {
      const available = await biometricLockService.isEnrolled();
      setIsBiometricAvailable(available);

      const prefEnabled = await biometricLockService.loadPreference();
      prefEnabledRef.current = prefEnabled && available;

      // Lock immediately if preference enabled
      if (prefEnabledRef.current) {
        setIsLocked(true);
      }
    })();
  }, []);

  // Listen for app foreground/background transitions
  useEffect(() => {
    const subscription = AppState.addEventListener(
      'change',
      async (nextState: AppStateStatus) => {
        const prev = appStateRef.current;
        appStateRef.current = nextState;

        // Transition to active from background/inactive
        if (nextState === 'active' && prev !== 'active') {
          if (prefEnabledRef.current && isBiometricAvailable) {
            setIsLocked(true);
          }
        }
      },
    );

    return () => subscription.remove();
  }, [isBiometricAvailable]);

  const onUnlock = useCallback(async (): Promise<boolean> => {
    try {
      const success = await biometricLockService.authenticate({
        promptMessage: 'Unlock ɳClaw',
      });
      if (success) {
        setIsLocked(false);
      }
      return success;
    } catch (err) {
      console.error('[useAppLock] Unlock failed:', err);
      // Remain locked on error — do not auto-unlock
      return false;
    }
  }, []);

  return { isLocked, onUnlock, isBiometricAvailable };
}
