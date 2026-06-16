import { test, expect } from '@playwright/test';

/**
 * Scenario 6: claw-web consumer wire smoke test.
 *
 * Verifies that @nself/claw-web components are mounted in nclaw/apps/web:
 * - ClawWebRoot renders with data-testid="claw-web-root"
 * - NetworkBanner mounts in DOM (may be hidden when online)
 * - No console errors from claw-web components on key pages
 *
 * SPORT: T-P3-E4-W3-S8-T05 — claw-web consumer wire
 */

test.describe('claw-web consumer smoke', () => {
  // Collect console errors for assertion at end of each test
  let consoleErrors: string[] = [];

  test.beforeEach(async ({ page }) => {
    consoleErrors = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });
  });

  test('ClawWebRoot mounts on the home page', async ({ page }) => {
    await page.goto('/');

    // ClawWebRoot wraps the entire app shell — data-testid is injected by the component
    const root = page.locator('[data-testid="claw-web-root"]');
    await expect(root).toBeAttached({ timeout: 10_000 });

    // No console errors from claw-web on load
    const clawErrors = consoleErrors.filter(
      (e) => e.includes('claw-web') || e.includes('ClawWeb') || e.includes('[ɳClaw'),
    );
    expect(clawErrors, `Unexpected claw-web console errors: ${clawErrors.join(', ')}`).toHaveLength(0);
  });

  test('ClawWebRoot mounts on the chat page', async ({ page }) => {
    // Navigate directly (no auth required for mount verification)
    await page.goto('/chat', { waitUntil: 'domcontentloaded' });

    const root = page.locator('[data-testid="claw-web-root"]');
    await expect(root).toBeAttached({ timeout: 10_000 });

    const clawErrors = consoleErrors.filter(
      (e) => e.includes('claw-web') || e.includes('ClawWeb') || e.includes('[ɳClaw'),
    );
    expect(clawErrors, `Unexpected claw-web console errors: ${clawErrors.join(', ')}`).toHaveLength(0);
  });

  test('NetworkBanner is absent when online (correct behavior)', async ({ page }) => {
    await page.goto('/');

    // NetworkBanner returns null when navigator.onLine is true (browser is online).
    // In a running E2E environment the test runner is online, so the banner should NOT render.
    // If it renders unexpectedly that indicates a false-offline detection bug.
    const root = page.locator('[data-testid="claw-web-root"]');
    await expect(root).toBeAttached({ timeout: 10_000 });

    // Verify no offline banner visible when we are online
    const offlineBanners = page.locator('text=Offline — Using cached data');
    await expect(offlineBanners).toHaveCount(0);
  });

  test('no claw-web import errors on settings page', async ({ page }) => {
    await page.goto('/settings', { waitUntil: 'domcontentloaded' });

    const clawErrors = consoleErrors.filter(
      (e) =>
        e.includes('claw-web') ||
        e.includes('ClawWeb') ||
        e.includes('[ɳClaw') ||
        e.includes('@nself/claw-web'),
    );
    expect(clawErrors, `Unexpected claw-web console errors: ${clawErrors.join(', ')}`).toHaveLength(0);
  });
});
