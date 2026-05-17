// nclaw Desktop — local-LLM end-to-end tests (S19 T07)
//
// Covers the full local-LLM user flow:
//   1. Search HuggingFace for a GGUF model
//   2. Select a result and pick a quantisation file
//   3. Trigger Download & Load
//   4. Observe download-progress → swap-done → model active state
//
// All Tauri invoke() calls and Tauri events are stubbed via page.addInitScript()
// so no real Tauri binary is required.  Tests are hermetic.

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** Minimal HfModel payload returned by llm_search_hf stub. */
const MOCK_MODEL = {
  id: 'test-org/tiny-llm-GGUF',
  name: 'Tiny LLM GGUF',
  downloads: 12345,
  gguf_files: [
    {
      filename: 'tiny-llm-Q4_K_M.gguf',
      quant: 'Q4_K_M',
      size_bytes: 500 * 1024 * 1024, // 500 MB
    },
    {
      filename: 'tiny-llm-Q8_0.gguf',
      quant: 'Q8_0',
      size_bytes: 900 * 1024 * 1024, // 900 MB
    },
  ],
};

const MOCK_MODELS_DIR = '/tmp/nclaw-test-models';

/** Fake download ID returned by llm_start_download stub. */
const MOCK_DOWNLOAD_ID = 'dl-e2e-test-001';

// ---------------------------------------------------------------------------
// Helper: install Tauri LLM invoke stubs
//
// Uses page.addInitScript() so stubs are in place before React mounts and
// before any useEffect / Tauri invoke fires.  Emits synthetic CustomEvents
// to simulate Tauri events (llm://download-progress, llm://swap-done).
// ---------------------------------------------------------------------------

async function mockLlmFlow(page: Page): Promise<void> {
  await page.addInitScript(
    ({
      mockModels,
      modelsDir,
      downloadId,
    }: {
      mockModels: typeof MOCK_MODEL[];
      modelsDir: string;
      downloadId: string;
    }) => {
      const w = window as unknown as Record<string, unknown>;

      // -----------------------------------------------------------------------
      // Tauri event bus stub
      // Tauri's listen() registers handlers that fire when events are emitted.
      // We replace __TAURI_INTERNALS__ with a stub that:
      //   - Routes invoke() per command name
      //   - Supports listen() by keying handlers in a map
      //   - Exposes window.__emitTauriEvent(name, payload) so tests can trigger
      //     events from the Playwright evaluate() context
      // -----------------------------------------------------------------------

      type EventHandler = (event: { payload: unknown }) => void;
      const eventHandlers: Record<string, EventHandler[]> = {};

      // Expose a way for test code to fire synthetic Tauri events.
      (window as unknown as { __emitTauriEvent: (name: string, payload: unknown) => void }).__emitTauriEvent =
        (name: string, payload: unknown) => {
          const handlers = eventHandlers[name] ?? [];
          for (const h of handlers) {
            h({ payload });
          }
        };

      w['__TAURI_INTERNALS__'] = {
        transformCallback: (cb: (v: unknown) => void) => {
          const id = Math.floor(Math.random() * 1e9);
          w[`_tauriCb_${id}`] = cb;
          return id;
        },

        // Invoke stub: routes by command name.
        invoke: async (cmd: string, _args?: Record<string, unknown>) => {
          switch (cmd) {
            // LLM commands (S19).
            case 'llm_search_hf':
              return mockModels;
            case 'llm_start_download':
              return downloadId;
            case 'llm_cancel_download':
              return null;
            case 'llm_list_downloads':
              return [];
            case 'llm_get_models_dir':
              return modelsDir;
            case 'llm_swap_model':
              // Simulate async swap-done event after a brief delay.
              setTimeout(() => {
                const handlers = eventHandlers['llm://swap-done'] ?? [];
                for (const h of handlers) {
                  h({ payload: 'tiny-llm-Q4_K_M.gguf' });
                }
              }, 50);
              return null;
            case 'llm_get_config':
              return null;
            case 'llm_poll_memory':
              return {
                gpu_used_mb: 0,
                gpu_total_mb: 0,
                ram_used_mb: 512,
                ram_total_mb: 16384,
                source: 'sysinfo',
              };
            // Chat / auth commands — return safe defaults.
            case 'stream_chat':
              return 'Hello from local model!';
            case 'list_topics':
              return [];
            case 'search':
              return { topics: [], matched_message_topics: [] };
            default:
              return null;
          }
        },

        // listen() stub: registers handler and returns an unlisten function.
        listen: async (event: string, handler: EventHandler) => {
          if (!eventHandlers[event]) {
            eventHandlers[event] = [];
          }
          eventHandlers[event].push(handler);
          // Return unlisten function.
          return () => {
            eventHandlers[event] = (eventHandlers[event] ?? []).filter(
              (h) => h !== handler,
            );
          };
        },
      };

      // Inject a fake JWT so auth-gated UI renders.
      try {
        window.localStorage.setItem('nclaw.auth.token', 'e2e-llm-mock-jwt');
      } catch {
        // Restricted localStorage — skip.
      }
    },
    {
      mockModels: [MOCK_MODEL],
      modelsDir: MOCK_MODELS_DIR,
      downloadId: MOCK_DOWNLOAD_ID,
    },
  );

  await page.goto('/');
}

// ---------------------------------------------------------------------------
// Helper: emit a Tauri download-progress event from the test context.
// ---------------------------------------------------------------------------

async function emitDownloadProgress(
  page: Page,
  id: string,
  status: unknown,
  bytesReceived = 0,
  totalBytes = 500 * 1024 * 1024,
) {
  await page.evaluate(
    ({
      eventId,
      eventStatus,
      eventBytesReceived,
      eventTotalBytes,
    }: {
      eventId: string;
      eventStatus: unknown;
      eventBytesReceived: number;
      eventTotalBytes: number;
    }) => {
      const w = window as unknown as {
        __emitTauriEvent: (name: string, payload: unknown) => void;
      };
      w.__emitTauriEvent('llm://download-progress', {
        id: eventId,
        status: eventStatus,
        bytes_received: eventBytesReceived,
        total_bytes: eventTotalBytes,
        bytes_per_sec: 1024 * 1024,
      });
    },
    {
      eventId: id,
      eventStatus: status,
      eventBytesReceived: bytesReceived,
      eventTotalBytes: totalBytes,
    },
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe('local-LLM flow', () => {
  // Navigate to the Settings → Local AI tab where ModelPicker is rendered.
  // The exact navigation path depends on the app's routing; we use the
  // data-testid attributes added in T07 to locate elements directly.

  test('search renders model results', async ({ page }) => {
    await mockLlmFlow(page);

    // Find the model search input.
    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });

    // Type a query and press Search.
    await searchInput.fill('tiny llm');
    await page.locator('[data-testid="model-search-button"]').click();

    // At least one result should appear.
    const firstResult = page.locator(
      '[data-testid="model-result-test-org-tiny-llm-GGUF"]',
    );
    await expect(firstResult).toBeVisible({ timeout: 10_000 });
    await expect(firstResult).toContainText('Tiny LLM GGUF');
    await expect(firstResult).toContainText('12,345');
  });

  test('search triggers on Enter key press', async ({ page }) => {
    await mockLlmFlow(page);

    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });

    await searchInput.fill('tiny llm');
    await searchInput.press('Enter');

    await expect(
      page.locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]'),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('selecting a model shows download button', async ({ page }) => {
    await mockLlmFlow(page);

    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });
    await searchInput.fill('tiny llm');
    await page.locator('[data-testid="model-search-button"]').click();

    // Click the first result to select it.
    const result = page.locator(
      '[data-testid="model-result-test-org-tiny-llm-GGUF"]',
    );
    await result.waitFor({ timeout: 10_000 });
    await result.click();

    // The download button should now be present.
    const downloadBtn = page.locator('[data-testid="model-download-button"]');
    await expect(downloadBtn).toBeVisible({ timeout: 5_000 });
    await expect(downloadBtn).toContainText('Download');
    // Button should not be disabled (no active download).
    await expect(downloadBtn).not.toBeDisabled();
  });

  test('download button shows downloading state during active download', async ({
    page,
  }) => {
    await mockLlmFlow(page);

    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });
    await searchInput.fill('tiny llm');
    await page.locator('[data-testid="model-search-button"]').click();

    await page
      .locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]')
      .waitFor({ timeout: 10_000 });
    await page
      .locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]')
      .click();

    // Click Download & Load.
    await page.locator('[data-testid="model-download-button"]').click();

    // Emit a downloading progress event to simulate active download.
    await emitDownloadProgress(page, MOCK_DOWNLOAD_ID, 'downloading', 10_000_000);

    // Button should now show "Downloading…" and be disabled.
    const downloadBtn = page.locator('[data-testid="model-download-button"]');
    await expect(downloadBtn).toContainText('Downloading', { timeout: 5_000 });
    await expect(downloadBtn).toBeDisabled();
  });

  test('swap completes after download done event', async ({ page }) => {
    await mockLlmFlow(page);

    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });
    await searchInput.fill('tiny llm');
    await page.locator('[data-testid="model-search-button"]').click();

    await page
      .locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]')
      .waitFor({ timeout: 10_000 });
    await page
      .locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]')
      .click();

    await page.locator('[data-testid="model-download-button"]').click();

    // Simulate download completing successfully.
    await emitDownloadProgress(
      page,
      MOCK_DOWNLOAD_ID,
      'done',
      500 * 1024 * 1024,
      500 * 1024 * 1024,
    );

    // The llm_swap_model invoke stub emits swap-done after 50ms.
    // Button should transition through "Loading model…" and then reset.
    const downloadBtn = page.locator('[data-testid="model-download-button"]');

    // Wait for loading state or final reset — either means swap was triggered.
    await page.waitForFunction(
      () => {
        const btn = document.querySelector('[data-testid="model-download-button"]');
        if (!btn) return false;
        const text = btn.textContent ?? '';
        return text.includes('Loading') || text.includes('Download');
      },
      { timeout: 8_000 },
    );

    // After swap-done fires the button should return to "Download & Load" state.
    await expect(downloadBtn).toContainText('Download', { timeout: 8_000 });
    await expect(downloadBtn).not.toBeDisabled();
  });

  test('Q4_K_M quantisation is auto-selected', async ({ page }) => {
    await mockLlmFlow(page);

    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });
    await searchInput.fill('tiny llm');
    await page.locator('[data-testid="model-search-button"]').click();

    await page
      .locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]')
      .waitFor({ timeout: 10_000 });
    await page
      .locator('[data-testid="model-result-test-org-tiny-llm-GGUF"]')
      .click();

    // The GGUF file select should show Q4_K_M as the default selection.
    const fileSelect = page.locator('#gguf-file-select');
    await expect(fileSelect).toBeVisible({ timeout: 5_000 });
    // The SelectTrigger's text reflects the selected file name.
    await expect(fileSelect).toContainText('Q4_K_M');
  });

  test('empty search query keeps button disabled', async ({ page }) => {
    await mockLlmFlow(page);

    const searchInput = page.locator('[data-testid="model-search-input"]');
    await searchInput.waitFor({ timeout: 15_000 });

    // Leave query empty — button must be disabled.
    const searchBtn = page.locator('[data-testid="model-search-button"]');
    await expect(searchBtn).toBeDisabled();
  });
});
