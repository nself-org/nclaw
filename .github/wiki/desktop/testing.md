# Desktop Testing

Run Playwright E2E suite with `pnpm e2e` in `nclaw/desktop/`. This launches a Vite dev server and a hermetic mock backend, then runs tests against the React frontend. Full Tauri-shell E2E (window APIs, native menus, OS dialogs) lands in S21.

## Test areas

Tests cover four areas:

- **App launch** — app renders within 5s and shows the chat input
- **Chat flow** — send message, receive streamed SSE reply, markdown renders
- **UI states** — empty / loading / loaded / error / saving / offline / syncing
- **Auth + streaming** — `mockAuth()` fixture injects a fake JWT and stubs the Tauri IPC bridge; streaming SSE chunks from the mock server appear in `.message-bubble` elements; persistence across page reload is confirmed

## Auth fixture

`tests/e2e/fixtures/auth.ts` exports two helpers:

- `mockAuth(page)` — navigates to `/`, stores a test JWT in `localStorage`, and patches `window.__TAURI_INTERNALS__.invoke` so that `stream_chat` calls are forwarded to the T11 mock backend at `http://127.0.0.1:5174` instead of a real Tauri binary.
- `getAuthState(page)` — reads `nclaw.auth.token` from `localStorage` for assertion.

## Selectors

| Element | Selector |
|---|---|
| Chat input | `[data-testid="chat-input"]` |
| Message bubble | `.message-bubble` |

## Mock backend (T11)

`tests/e2e/mock/server.ts` runs on port 5174 and is auto-started by the Playwright `webServer` config. Endpoints:

| Method | Path | Response |
|---|---|---|
| POST | `/api/chat/stream` | SSE: `{"chunk":"Hello"}`, `{"chunk":" world"}`, `[DONE]` |
| GET | `/api/topics` | JSON array of two fixture topics |
| POST | `/api/topics` | 201 with new topic |
| DELETE | `/api/topics/:id` | 204 |
| GET | `/api/settings` | `{"theme":"dark","language":"en","notifications":true}` |
| POST | `/api/settings` | `{"ok":true}` |

## CI

CI runs on macOS, Ubuntu, and Windows. Failed runs upload artifact `playwright-report-*.zip`.

See `playwright.config.ts` for full configuration.
