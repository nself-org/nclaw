/**
 * Purpose: Gate ɳClaw mobile behind biometric authentication on app resume.
 * Inputs: None (reads user pref from expo-secure-store).
 * Outputs: { isAuthenticated, isEnrolled, prefEnabled, setPrefEnabled, authenticate }.
 * Constraints: Biometrics require physical device; graceful fallback when not enrolled.
 *   Does NOT crash when biometrics unavailable — falls through to allow access.
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-biometric-auth
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import * as LocalAuthentication from 'expo-local-authentication';
import * as SecureStore from 'expo-secure-store';
import { AppState, AppStateStatus } from 'react-native';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface UseBiometricAuthReturn {
  /** True when the session has passed biometric (or biometrics not required/enrolled) */
  isAuthenticated: boolean;
  /** Whether the device has biometrics enrolled */
  isEnrolled: boolean;
  /** Whether the user has enabled biometric gating in settings */
  prefEnabled: boolean;
  /** Toggle biometric preference */
  setPrefEnabled: (enabled: boolean) => Promise<void>;
  /** Manually trigger authenticate (e.g. from settings or re-lock) */
  authenticate: () => Promise<boolean>;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const BIOMETRIC_PREF_KEY = 'nclaw_biometric_enabled';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function loadPref(): Promise<boolean> {
  try {
    const val = await SecureStore.getItemAsync(BIOMETRIC_PREF_KEY);
    return val === 'true';
  } catch {
    return false;
  }
}

async function savePref(enabled: boolean): Promise<void> {
  await SecureStore.setItemAsync(BIOMETRIC_PREF_KEY, enabled ? 'true' : 'false');
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

export function useBiometricAuth(): UseBiometricAuthReturn {
  const [isAuthenticated, setIsAuthenticated] = useState(true); // optimistic — locked on first active if pref on
  const [isEnrolled, setIsEnrolled] = useState(false);
  const [prefEnabled, setPrefState] = useState(false);

  const appStateRef = useRef<AppStateStatus>(AppState.currentState);
  const prefRef = useRef(false);
  const enrolledRef = useRef(false);

  // Bootstrap: check enrollment + load pref
  useEffect(() => {
    (async () => {
      const [hardwareAvailable, enrolled, pref] = await Promise.all([
        LocalAuthentication.hasHardwareAsync(),
        LocalAuthentication.isEnrolledAsync(),
        loadPref(),
      ]);

      const canUse = hardwareAvailable && enrolled;
      setIsEnrolled(canUse);
      enrolledRef.current = canUse;

      const effectivePref = pref && canUse;
      setPrefState(effectivePref);
      prefRef.current = effectivePref;

      // If pref enabled, lock immediately so the first resume triggers auth
      if (effectivePref) {
        setIsAuthenticated(false);
        // Trigger immediate auth on initial load
        await runAuthenticate(setIsAuthenticated);
      }
    })();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Lock on background → foreground transition
  useEffect(() => {
    const subscription = AppState.addEventListener(
      'change',
      async (nextState: AppStateStatus) => {
        const prev = appStateRef.current;
        appStateRef.current = nextState;

        // Became active from background/inactive
        if (nextState === 'active' && prev !== 'active') {
          if (prefRef.current && enrolledRef.current) {
            setIsAuthenticated(false);
            await runAuthenticate(setIsAuthenticated);
          }
        }
      },
    );

    return () => subscription.remove();
  }, []);

  const authenticate = useCallback(async (): Promise<boolean> => {
    return runAuthenticate(setIsAuthenticated);
  }, []);

  const setPrefEnabled = useCallback(async (enabled: boolean): Promise<void> => {
    // Verify enrollment before enabling
    if (enabled && !enrolledRef.current) {
      console.warn('[nclaw-biometric] Cannot enable — biometrics not enrolled');
      return;
    }
    await savePref(enabled);
    prefRef.current = enabled;
    setPrefState(enabled);

    // Immediately authenticate when enabling
    if (enabled) {
      setIsAuthenticated(false);
      await runAuthenticate(setIsAuthenticated);
    } else {
      // Disabling — unlock immediately
      setIsAuthenticated(true);
    }
  }, []);

  return { isAuthenticated, isEnrolled, prefEnabled, setPrefEnabled, authenticate };
}

// ─── Shared authenticate runner ───────────────────────────────────────────────

async function runAuthenticate(
  setIsAuthenticated: (v: boolean) => void,
): Promise<boolean> {
  try {
    const result = await LocalAuthentication.authenticateAsync({
      promptMessage: 'Unlock ɳClaw',
      fallbackLabel: 'Use Passcode',
      cancelLabel: 'Cancel',
      disableDeviceFallback: false,
    });

    if (result.success) {
      setIsAuthenticated(true);
      return true;
    }

    // User cancelled — remain locked; do not crash
    return false;
  } catch (err) {
    // Hardware error, simulator, etc. — fall through and allow access
    console.warn('[nclaw-biometric] Auth error (graceful fallback):', err);
    setIsAuthenticated(true);
    return true;
  }
}
