/**
 * nclaw/mobile — Auth strategy singleton.
 *
 * Purpose: Create and export the NativeAuthStrategy instance wired to
 *          expo-secure-store for JWT persistence. Created once, shared app-wide.
 * Inputs:  expo-secure-store SecureStore adapter.
 * Outputs: NativeAuthStrategy singleton + SecureStore adapter.
 * Constraints:
 *   - NEVER log accessToken/refreshToken.
 *   - SECURE_STORE_KEYS used for all storage keys — no raw string literals.
 *   - SecureStoreInterface adapter maps expo-secure-store API to @nself/auth-core interface.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */

import * as ExpoSecureStore from 'expo-secure-store';
import {
  createNativeAuthStrategy,
  type SecureStoreInterface,
} from '@nself/auth-core';

/** expo-secure-store adapter implementing SecureStoreInterface */
const expoSecureStore: SecureStoreInterface = {
  getItem: async (key: string): Promise<string | null> => {
    return ExpoSecureStore.getItemAsync(key);
  },
  setItem: async (key: string, value: string): Promise<void> => {
    await ExpoSecureStore.setItemAsync(key, value);
  },
  removeItem: async (key: string): Promise<void> => {
    await ExpoSecureStore.deleteItemAsync(key);
  },
};

/** Singleton NativeAuthStrategy instance for the entire app */
export const authStrategy = createNativeAuthStrategy(expoSecureStore, {
  authBaseUrl: `${process.env.EXPO_PUBLIC_NSELF_API_URL ?? 'http://localhost:3710'}/v1/auth`,
});
