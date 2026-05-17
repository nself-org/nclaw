/**
 * Auth fixtures for nclaw e2e tests.
 *
 * mockAuth() injects a fake JWT into the page and stubs
 * window.__TAURI_INTERNALS__ so that invoke('stream_chat', ...) routes to
 * the T11 mock server at http://127.0.0.1:5174 instead of a real Tauri IPC.
 * This keeps tests hermetic — no real Tauri binary required.
 *
 * getAuthState() reads back the injected auth token for assertion.
 */

import type { Page } from '@playwright/test';

const MOCK_TOKEN = 'e2e-mock-jwt.test-only';
const MOCK_SERVER = 'http://127.0.0.1:5174';

/**
 * Set up a fake auth session and stub the Tauri invoke bridge so that
 * stream_chat calls are forwarded to the mock SSE server.
 * Call in test.beforeEach.
 *
 * Uses page.addInitScript so the stub is installed before React mounts and
 * before any Tauri invoke() calls fire from component effects.
 */
export async function mockAuth(page: Page): Promise<void> {
  // Install the Tauri stub via addInitScript so it runs before any page script.
  // This ensures Sidebar.load() and other early invoke() calls resolve to null
  // rather than throwing, which would crash the React component tree.
  await page.addInitScript(
    ({ token, mockServer }: { token: string; mockServer: string }) => {
      // Store fake JWT so auth-gated UI renders.
      try {
        window.localStorage.setItem('nclaw.auth.token', token);
      } catch {
        // localStorage may be restricted in some configurations — skip silently.
      }

      // Stub window.__TAURI_INTERNALS__ so invoke() resolves without a real
      // Tauri binary.  stream_chat is forwarded to the T11 SSE mock server.
      // All other commands resolve to null (safe no-op for page rendering).
      const w = window as unknown as Record<string, unknown>;
      w['__TAURI_INTERNALS__'] = {
        transformCallback: (callback: (v: unknown) => void) => {
          // Minimal stub — return a numeric handle.
          const id = Math.floor(Math.random() * 1e9);
          w[`_tauriCb_${id}`] = callback;
          return id;
        },
        invoke: async (cmd: string, args?: Record<string, unknown>) => {
          if (cmd === 'stream_chat') {
            // Forward to T11 mock; chatTransport wraps the Tauri reply, so we
            // return a plain string that it uses as the assistant text.
            // The mock handles the SSE protocol — we just signal "ok".
            const res = await fetch(`${mockServer}/api/chat/stream`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(args ?? {}),
            });
            if (!res.ok) throw new Error(`mock stream_chat: ${res.status}`);
            // Drain SSE and concatenate chunks.
            const reader = res.body?.getReader();
            if (!reader) return '(no body)';
            const decoder = new TextDecoder();
            let text = '';
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              const chunk = decoder.decode(value, { stream: true });
              // Parse SSE lines: "data: {...}\n\n"
              for (const line of chunk.split('\n')) {
                const trimmed = line.trim();
                if (!trimmed.startsWith('data:')) continue;
                const payload = trimmed.slice(5).trim();
                if (payload === '[DONE]') break;
                try {
                  const parsed = JSON.parse(payload) as { chunk?: string };
                  if (parsed.chunk) text += parsed.chunk;
                } catch {
                  // Ignore non-JSON SSE lines.
                }
              }
            }
            return text || 'Hello world';
          }
          // Commands that return arrays — return empty arrays to avoid
          // "not iterable" crashes in components that iterate over results.
          if (cmd === 'list_topics' || cmd === 'search') {
            return cmd === 'search'
              ? { topics: [], matched_message_topics: [] }
              : [];
          }
          // Default: return null for any other Tauri command.
          return null;
        },
      };
    },
    { token: MOCK_TOKEN, mockServer: MOCK_SERVER },
  );

  await page.goto('/');
}

/**
 * Return the auth token currently stored in localStorage.
 * Returns null if no token is set.
 */
export async function getAuthState(page: Page): Promise<string | null> {
  return page.evaluate(() => {
    try {
      return window.localStorage.getItem('nclaw.auth.token');
    } catch {
      return null;
    }
  });
}
