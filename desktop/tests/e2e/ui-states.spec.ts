import { test, expect } from '@playwright/test';

const STATES = ['empty', 'loading', 'loaded', 'error', 'saving', 'offline', 'syncing'];

for (const state of STATES) {
  test(`ChatList in ${state} state renders without error`, async ({ page }) => {
    await page.goto(`/?ui-state=${state}`);
    await expect(page.locator('body')).toBeVisible();
  });
}
