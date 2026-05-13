# Desktop Acceptance Criteria

v1.1.1 desktop acceptance via Playwright E2E:

1. **Launch** — app loads main view within 5s, ɳClaw heading visible
2. **Chat** — user sends message, receives stub reply within 10s, markdown renders
3. **UI States** — all 7 states (empty/loading/loaded/error/saving/offline/syncing) render without error

CI runs on 3 OS (macOS/Ubuntu/Windows). All tests must pass before merge. Failed runs preserve artifacts for debugging.
