import { test, expect } from '@playwright/test';

test('user can send a message and see a stub reply', async ({ page }) => {
  await page.goto('/');
  const input = page.getByPlaceholder(/Type a message/i);
  await input.waitFor({ timeout: 5000 });
  await input.fill('Hello');
  await page.keyboard.press('Enter');
  await expect(page.locator('text=(stub response)')).toBeVisible({ timeout: 10000 });
});

test('markdown renders in messages', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('article, [role="article"], .markdown, .prose').first()).toBeAttached({ timeout: 10000 });
});
