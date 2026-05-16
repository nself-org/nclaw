import { test, expect } from '@playwright/test';

test('body visible with addInitScript empty', async ({ page }) => {
  await page.addInitScript('/* empty */');
  await page.goto('/');
  await expect(page.locator('body')).toBeVisible({ timeout: 5000 });
});

test('body visible with addInitScript that sets something', async ({ page }) => {
  await page.addInitScript('window.__TEST__ = true;');
  await page.goto('/');
  await expect(page.locator('body')).toBeVisible({ timeout: 5000 });
});

test('body visible with NO addInitScript', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).toBeVisible({ timeout: 5000 });
});
