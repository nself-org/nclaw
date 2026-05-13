import { test, expect } from '@playwright/test';

test('app loads main view within 5s', async ({ page }) => {
  const start = Date.now();
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /ɳClaw/i })).toBeVisible({ timeout: 5000 });
  expect(Date.now() - start).toBeLessThan(5000);
});

test('main window has expected sections', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('text=ɳClaw').first()).toBeVisible();
});
