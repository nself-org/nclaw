/**
 * register-sw.ts
 *
 * Purpose: Register the claw-web service worker for offline support.
 *          Called once from the root layout on the client side.
 *
 * Constraints: Only runs in production to avoid dev-mode caching confusion.
 */

export function registerServiceWorker(): void {
  if (
    typeof window === 'undefined' ||
    !('serviceWorker' in navigator) ||
    process.env.NODE_ENV !== 'production'
  ) {
    return;
  }

  window.addEventListener('load', () => {
    navigator.serviceWorker
      .register('/service-worker.js')
      .catch(() => {
        // SW registration failure is non-fatal — app works without it.
      });
  });
}
