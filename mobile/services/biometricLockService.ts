/**
 * biometricLockService — Wrapper around biometric authentication provider.
 *
 * Purpose: Provide a typed, platform-agnostic interface to biometric auth
 *   via @nself/native-bridge. Consumed by useAppLock hook and settings.
 * Inputs:  Reason string for OS prompt; preference store operations.
 * Outputs: Result<boolean> indicating auth success/failure; enrollment status.
 * Constraints: Graceful degradation on non-enrolled devices or unavailable biometrics.
 * SPORT: F08-SERVICE-INVENTORY — nclaw-mobile-biometric-lock-service
 */

import { ExpoLocalAuth } from '@nself/native-bridge';
import * as SecureStore from 'expo-secure-store';

const BIOMETRIC_PREF_KEY = 'nclaw_biometric_enabled';

export interface BiometricLockServiceConfig {
  promptMessage?: string;
  fallbackLabel?: string;
  cancelLabel?: string;
}

/**
 * BiometricLockService — encapsulates biometric state + prefs.
 */
export class BiometricLockService {
  private provider = new ExpoLocalAuth();

  /**
   * Check if device has enrolled biometrics available.
   */
  async isEnrolled(): Promise<boolean> {
    return this.provider.isAvailable();
  }

  /**
   * Authenticate user with biometric.
   * @param config Optional UI configuration (labels, message).
   * @returns true if authenticated, false if cancelled, throws on unexpected error.
   */
  async authenticate(config?: BiometricLockServiceConfig): Promise<boolean> {
    const reason = config?.promptMessage || 'Unlock ɳClaw';
    const result = await this.provider.authenticate(reason);

    if (result.ok) {
      return result.value;
    }

    // On error, gracefully allow access (fallback)
    console.warn('[BiometricLockService] Auth failed:', result.error);
    return false;
  }

  /**
   * Load user's biometric preference from secure storage.
   */
  async loadPreference(): Promise<boolean> {
    try {
      const val = await SecureStore.getItemAsync(BIOMETRIC_PREF_KEY);
      return val === 'true';
    } catch {
      return false;
    }
  }

  /**
   * Save user's biometric preference to secure storage.
   * @param enabled Whether biometric lock should be enabled.
   */
  async savePreference(enabled: boolean): Promise<void> {
    try {
      await SecureStore.setItemAsync(BIOMETRIC_PREF_KEY, enabled ? 'true' : 'false');
    } catch (err) {
      console.error('[BiometricLockService] Failed to save preference:', err);
      throw err;
    }
  }
}

/**
 * Singleton instance.
 */
export const biometricLockService = new BiometricLockService();
