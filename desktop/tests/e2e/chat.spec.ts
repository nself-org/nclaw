import { test, expect } from '@playwright/test';
import { mockAuthenticatedSession } from './fixtures/auth';

// Both tests require an authenticated session: App.tsx only mounts
// ChatContainer (the composer + message list) once useAuth() resolves to
// 'authenticated' (see desktop/src/App.tsx Shell()). A fresh, unauthenticated
// page has no chat UI at all, so every test here seeds a session first.

test('user can send a message and see a stub reply', async ({ page }) => {
  await mockAuthenticatedSession(page);
  await page.goto('/');

  // Real placeholder string is @nself/i18n's desktop.nclaw.messagePlaceholder
  // ("Message ɳClaw…"), wired in InputArea.tsx via useNselfTranslation().
  const input = page.getByPlaceholder(/Message ɳClaw/i);
  await input.waitFor({ timeout: 5000 });
  await input.fill('Hello');
  await page.keyboard.press('Enter');

  // stream_chat's real Rust command still returns NotImplemented pending
  // S15.T17 (desktop/src-tauri/src/commands/chat.rs); the mocked Tauri
  // bridge in fixtures/auth.ts stands in for it with the same placeholder
  // text so this test exercises the real send -> render pipeline (useChat,
  // ChatContainer, ChatList, MessageBubble) without depending on a native
  // Tauri host, which Playwright cannot drive.
  await expect(page.locator('text=(stub response)')).toBeVisible({ timeout: 10000 });
});

test('markdown renders in messages', async ({ page }) => {
  await mockAuthenticatedSession(page);
  await page.goto('/');

  const input = page.getByPlaceholder(/Message ɳClaw/i);
  await input.waitFor({ timeout: 5000 });
  await input.fill('**bold text**');
  await page.keyboard.press('Enter');

  // MessageBubble renders message content through react-markdown
  // (remark-gfm), which turns **bold text** into a real <strong> element.
  // This fails again if MessageBubble stops rendering markdown (e.g. reverts
  // to a plain text node), unlike a generic container-class selector that
  // could match unrelated markup.
  await expect(page.locator('strong', { hasText: 'bold text' })).toBeAttached({
    timeout: 10000,
  });
});
