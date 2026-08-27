/**
 * Purpose: Seed an authenticated session for nclaw desktop E2E tests.
 * Inputs:  Playwright Page.
 * Outputs: Injects a TokenPair into localStorage (the same keys
 *          NativeAuthStrategy/SecureStoreInterface read from — see
 *          desktop/src/lib/auth.ts and @nself/auth-core/src/native.helpers.ts
 *          SECURE_STORE_KEYS) before the page's own scripts run, and stubs
 *          window.__TAURI_INTERNALS__ so invoke() resolves without a real
 *          Tauri binary (Playwright drives a plain Chromium window, which
 *          has no Tauri IPC bridge at all).
 * Constraints:
 *   - Must run via page.addInitScript, before React mounts and before
 *     NativeAuthStrategy.init() reads SecureStore, or the app renders
 *     'loading' -> 'unauthenticated' and the chat UI never appears.
 *   - expiresAt is set far in the future so the proactive refresh loop
 *     (DEFAULT_REFRESH_BUFFER_MS before expiry) never fires mid-test and
 *     tries to hit a real auth server that doesn't exist in CI.
 *   - The JWT signature is not verified client-side (decodeUserFromJwt only
 *     reads the payload), so any syntactically valid three-part token works.
 */

import type { Page } from '@playwright/test';

// Mirrors @nself/auth-core SECURE_STORE_KEYS (native.helpers.ts) — desktop's
// localSecureStore (desktop/src/lib/auth.ts) is a thin localStorage wrapper
// around the same keys.
const SECURE_STORE_KEYS = {
  ACCESS_TOKEN: '@nself/auth-core/accessToken',
  REFRESH_TOKEN: '@nself/auth-core/refreshToken',
  EXPIRES_AT: '@nself/auth-core/expiresAt',
} as const;

/**
 * Seed a valid, far-from-expiry TokenPair and stub the Tauri IPC bridge so
 * the app boots into the 'authenticated' state and can call stream_chat
 * without a native Tauri host. Call before page.goto('/').
 */
export async function mockAuthenticatedSession(page: Page): Promise<void> {
  await page.addInitScript(
    ({ accessKey, refreshKey, expiresKey }) => {
      function base64url(obj: Record<string, unknown>): string {
        return btoa(JSON.stringify(obj))
          .replace(/\+/g, '-')
          .replace(/\//g, '_')
          .replace(/=+$/, '');
      }

      const header = base64url({ alg: 'HS256', typ: 'JWT' });
      const payload = base64url({
        sub: 'e2e-test-user-id',
        email: 'e2e@example.test',
        display_name: 'E2E Test User',
        'https://hasura.io/jwt/claims': {
          'x-hasura-allowed-roles': ['user'],
          'x-hasura-default-role': 'user',
        },
      });
      const fakeJwt = `${header}.${payload}.e2e-test-signature`;

      window.localStorage.setItem(accessKey, fakeJwt);
      window.localStorage.setItem(refreshKey, 'e2e-test-refresh-token');
      // 24h out — well past DEFAULT_REFRESH_BUFFER_MS (60s), so the refresh
      // loop schedules for tomorrow and never fires during the test run.
      window.localStorage.setItem(expiresKey, String(Date.now() + 24 * 60 * 60 * 1000));

      // Stub the Tauri IPC bridge. Real command implementations are Rust
      // (desktop/src-tauri/src/commands/*.rs); Playwright drives a plain
      // browser window with no native host, so invoke() would otherwise
      // throw "window.__TAURI_INTERNALS__ is undefined" before React can
      // even render the composer.
      const w = window as unknown as Record<string, unknown>;
      w.__TAURI_INTERNALS__ = {
        transformCallback: (callback: (value: unknown) => void): number => {
          const id = Math.floor(Math.random() * 1e9);
          (w as Record<string, unknown>)[`_tauriCb_${id}`] = callback;
          return id;
        },
        invoke: async (cmd: string): Promise<unknown> => {
          if (cmd === 'stream_chat') {
            // stream_chat's real Rust implementation is a stub returning
            // NotImplemented (see desktop/src-tauri/src/commands/chat.rs,
            // awaiting S15.T17). Mirror that shape here rather than a
            // hand-picked success value, so this fixture does not claim
            // more of the backend works than actually does.
            return '(stub response)';
          }
          return null;
        },
      };
    },
    {
      accessKey: SECURE_STORE_KEYS.ACCESS_TOKEN,
      refreshKey: SECURE_STORE_KEYS.REFRESH_TOKEN,
      expiresKey: SECURE_STORE_KEYS.EXPIRES_AT,
    },
  );
}
