# Desktop Testing

Run Playwright E2E suite with `pnpm e2e` in `nclaw/desktop/`. This launches a Vite dev server and runs tests against the React frontend. Full Tauri-shell E2E (window APIs, native menus, OS dialogs) lands in S21.

Tests cover three areas: app launch (within 5s), chat flow (send message, receive stub, markdown render), and UI states (empty/loading/loaded/error/saving/offline/syncing). CI runs on macOS, Ubuntu, and Windows.

See `playwright.config.ts` for configuration. Failed runs upload artifact `playwright-report-*.zip`.
