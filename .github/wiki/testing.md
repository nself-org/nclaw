# Testing Guide - claw

## 1. Unit Tests

```bash
cd libs/libnclaw
cargo test
```

For Flutter app:
```bash
cd app
flutter test
```

Expected runtime: ~30s (Rust), ~60s (Flutter). Coverage output in `target/llvm-cov/` (Rust) or `coverage/` (Flutter).

## 2. Integration Tests

Requires Docker for testcontainers.

```bash
cd backend
nself start   # starts Postgres, Hasura, Redis
cd ../test
go test -tags=integration -count=1 ./...
```

## 3. E2E Tests

### Desktop (Tauri 2 + React)

Playwright tests for the nclaw desktop app. Tests mock Tauri IPC via `window.__TAURI_INTERNALS__` so no native Tauri runtime is needed.

```bash
cd desktop

# Install Playwright browsers (first time only)
pnpm exec playwright install chromium

# Run all e2e tests
pnpm exec playwright test

# Run specific spec
pnpm exec playwright test tests/e2e/sidebar.spec.ts

# Run with headed browser (debug)
pnpm exec playwright test --headed
```

The Vite dev server at `:5173` starts automatically. `reuseExistingServer: true` reuses an already-running server in dev.

**Spec coverage:**

| Spec | Scenarios | Coverage |
|------|-----------|---------|
| `sidebar.spec.ts` | 11 | Topic tree render, expand/collapse, set-active, context menu, search/filter, drag-reorder, command palette nav |
| `chat.spec.ts` | — | Chat container, message streaming |
| `settings.spec.ts` | — | Settings overlay, theme, provider config |
| `theme.spec.ts` | — | Theme switch, accent color, persistence |

**Tauri IPC mock pattern:**

```typescript
await page.addInitScript(() => {
  (window as any).__TAURI_INTERNALS__ = {
    transformCallback(callback, once) { return Math.random(); },
    unregisterCallback(id) {},
    async invoke(cmd, args) {
      if (cmd === 'list_topics') return [...];
      return null;
    },
  };
});
```

The mock must be injected via `addInitScript()` BEFORE `page.goto()` so it's available when `@tauri-apps/api/core` calls `invoke()` on mount.

### Web client (legacy Flutter web)

```bash
# Web (Flutter CanvasKit)
cd app/web
pnpm exec playwright install
pnpm exec playwright test

# Mobile (iOS)
maestro test flows/
```

Environment variables needed:
- `NSELF_TEST_URL` - backend URL (default: http://localhost)
- `NSELF_PLUGIN_LICENSE_KEY` - valid test license key

## 4. Performance Benchmarks

```bash
cd test/perf
k6 run chat-throughput.js
k6 run memory-retrieval.js
```

Compare against baseline: `k6 run --out json=results.json chat-throughput.js`

## 5. Adding a New Test

- Unit tests: place next to source file as `*_test.go` (Go), `*_test.dart` (Flutter), `*.test.rs` (Rust)
- Integration tests: `test/integration/flows/` with `//go:build integration` tag
- Fixtures: use shared fixtures from `plugins-pro/test/fixtures/` via `harness.SeedSQL()`
- Factories: use `plugins-pro/test/factories/` for programmatic test data
- Snapshots: use `plugins-pro/test/snapshot/` package, stored in `__snapshots__/` next to test

## 6. CI Workflow Map

| Workflow | Trigger | What it runs |
|----------|---------|-------------|
| `ci.yml` | Push, PR | Unit tests, lint, type check |
| `integration.yml` | PR to main | Integration flows with testcontainers |
| `coverage.yml` | Push to main | Tarpaulin coverage, Codecov upload |
| `coverage-diff-gate.yml` | PR | Coverage diff comment, -2% block |

## 7. Common Flakes and Fixes

| Flake | Cause | Fix |
|-------|-------|-----|
| `testcontainers timeout` | Docker daemon slow | Increase `WithStartupTimeout` or use `TESTCONTAINERS_REUSE=1` |
| `ollama model not found` | Model not pulled | Pre-pull in CI: `docker pull ollama/ollama:0.4.2` |
| `port already in use` | Parallel test collision | Use random ports via testcontainers (default) |
