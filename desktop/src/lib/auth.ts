/**
 * Purpose: Singleton NativeAuthStrategy for ɳClaw desktop (Tauri 2).
 *          Uses @nself/auth-core NativeAuthStrategy with a localStorage-backed
 *          SecureStore so tokens persist across app restarts.
 * Inputs:  VITE_NSELF_AUTH_URL from env.
 * Outputs: authStrategy singleton consumed by NselfAuthProvider in main.tsx.
 * Constraints:
 *   - createNativeAuthStrategy() MUST be called once at module level, before React mounts.
 *   - NEVER log jwt / accessToken fields — auth-core enforces this but callers must comply.
 *   - Keys are namespaced (SECURE_STORE_KEYS from auth-core) to avoid collisions.
 *   - Desktop: localStorage is acceptable as the app has no shared-origin attack surface
 *     (Tauri CSP restricts all content to 'self' + tauri: scheme).
 *   - Future: migrate to @tauri-apps/plugin-store + OS keychain for production hardening.
 * SPORT: F08-SERVICE-INVENTORY.md — nclaw-desktop-auth
 */

import { createNativeAuthStrategy, type SecureStoreInterface } from '@nself/auth-core';

// ─── localStorage SecureStore adapter ─────────────────────────────────────────
// SecureStoreInterface uses async get/set/delete; localStorage is sync but we wrap
// in Promise.resolve() to satisfy the interface contract.

const localSecureStore: SecureStoreInterface = {
  async get(key: string): Promise<string | null> {
    return Promise.resolve(localStorage.getItem(key));
  },
  async set(key: string, value: string): Promise<void> {
    localStorage.setItem(key, value);
  },
  async delete(key: string): Promise<void> {
    localStorage.removeItem(key);
  },
};

// ─── Auth strategy singleton ───────────────────────────────────────────────────

export const authStrategy = createNativeAuthStrategy(localSecureStore, {
  authBaseUrl: import.meta.env.VITE_NSELF_AUTH_URL ?? 'https://api.nself.org/v1/auth',
});
