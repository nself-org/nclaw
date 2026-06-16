/// <reference lib="webworker" />

/**
 * service-worker.ts
 *
 * Purpose: Intercept GET requests to /api/claw/conversations so claw-web can
 *          serve cached conversation data when the user is offline.
 *
 * Strategy: Network-first with IndexedDB offline fallback.
 *   - Online  → pass through to network; cache result in IndexedDB (via page JS).
 *   - Offline → return 503 JSON stub so page JS can fall back to IndexedDB.
 *
 * Constraints:
 *  - Service workers cannot import ES modules directly — this is compiled by
 *    Next.js via next-pwa or manually registered as a classic SW.
 *  - IndexedDB writes happen in the page, not here. The SW only signals
 *    offline status so the page can switch to the cache read path.
 *
 * SPORT: offline cache feature — see REGISTRY-WEB-SURFACES.md nclaw claw-web row.
 */

/* eslint-disable no-restricted-globals */

declare const self: ServiceWorkerGlobalScope;

const CACHE_NAME = 'nclaw-shell-v1';

// Static shell assets to pre-cache on install.
const SHELL_ASSETS: string[] = [
  '/',
  '/history',
  '/knowledge',
  '/call',
];

// ---------------------------------------------------------------------------
// Install — pre-cache shell routes
// ---------------------------------------------------------------------------

self.addEventListener('install', (event: ExtendableEvent) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

// ---------------------------------------------------------------------------
// Activate — claim all clients immediately
// ---------------------------------------------------------------------------

self.addEventListener('activate', (event: ExtendableEvent) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      );
      await self.clients.claim();
    })()
  );
});

// ---------------------------------------------------------------------------
// Fetch — network-first; offline stub for conversation API
// ---------------------------------------------------------------------------

self.addEventListener('fetch', (event: FetchEvent) => {
  const { request } = event;

  // Only intercept same-origin API GET requests for conversations.
  if (
    request.method !== 'GET' ||
    !request.url.includes('/api/claw/conversations')
  ) {
    // For navigation requests, return cached shell on failure.
    if (request.mode === 'navigate') {
      event.respondWith(
        fetch(request).catch(() =>
          caches.match('/').then((r) => r ?? new Response('Offline', { status: 503 }))
        )
      );
    }
    return;
  }

  // Network-first for conversations API.
  event.respondWith(
    fetch(request).catch(() => {
      // Offline — return a 503 JSON signal so page JS reads IndexedDB.
      return new Response(JSON.stringify({ offline: true }), {
        status: 503,
        headers: { 'Content-Type': 'application/json', 'X-Nclaw-Offline': '1' },
      });
    })
  );
});
