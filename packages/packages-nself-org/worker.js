/**
 * packages.nself.org — Cloudflare Worker
 *
 * Serves Tauri auto-updater manifests and desktop release artifacts from R2.
 * Routes:
 *   GET /desktop/latest-{macos,windows,linux}.json  → updater manifests (Ed25519-signed)
 *   GET /desktop/{version}/{platform}/{filename}     → release binaries (DMG/MSI/AppImage/deb)
 *   GET /health                                      → {"status":"ok"}
 *
 * Deployment: UA-12 (user-authorized P104 gate).
 * Wrangler config: packages-nself-org/wrangler.toml
 * R2 bucket: packages-nself-org
 *
 * @see nclaw/.github/workflows/publish-updater.yml   — uploads manifests
 * @see nclaw/.github/workflows/publish-r2.yml        — uploads binaries
 */

const BUCKET_NAME = 'packages-nself-org';

/** Map platform shorthand to updater manifest filename. */
const UPDATER_MANIFESTS = {
  macos: 'latest-macos.json',
  windows: 'latest-windows.json',
  linux: 'latest-linux.json',
};

/** CORS headers for Tauri updater requests (same-origin not applicable for native app). */
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default {
  /**
   * @param {Request} request
   * @param {Object} env  — bindings from wrangler.toml: env.PACKAGES_BUCKET (R2Bucket)
   * @param {Object} ctx
   * @returns {Promise<Response>}
   */
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, ''); // strip leading slash

    // OPTIONS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // Only GET and HEAD are supported
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405, headers: CORS_HEADERS });
    }

    // --- Health check ---
    if (path === 'health' || path === '') {
      return new Response(JSON.stringify({ status: 'ok', service: 'packages.nself.org' }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // --- Updater manifest shorthand: /desktop/latest-{platform}.json ---
    // Tauri updater pings: https://packages.nself.org/desktop/latest-macos.json
    const manifestMatch = path.match(/^desktop\/latest-(macos|windows|linux)\.json$/);
    if (manifestMatch) {
      const platform = manifestMatch[1];
      const r2Key = `desktop/${UPDATER_MANIFESTS[platform]}`;
      return serveR2Object(env, r2Key, 'application/json', ctx);
    }

    // --- Platform alias: /desktop/{platform}/latest.json ---
    const platformLatestMatch = path.match(/^desktop\/(macos|windows|linux)\/latest\.json$/);
    if (platformLatestMatch) {
      const platform = platformLatestMatch[1];
      const r2Key = `desktop/${UPDATER_MANIFESTS[platform]}`;
      return serveR2Object(env, r2Key, 'application/json', ctx);
    }

    // --- General R2 passthrough: /desktop/{version}/{platform}/{filename} ---
    // Used for binary downloads referenced in updater manifests.
    if (path.startsWith('desktop/')) {
      return serveR2Object(env, path, guessContentType(path), ctx);
    }

    // --- 404 for anything else ---
    return new Response(
      JSON.stringify({ error: 'Not Found', path: `/${path}` }),
      {
        status: 404,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      }
    );
  },
};

/**
 * Fetch an object from the bound R2 bucket and stream it as a Response.
 * @param {Object} env
 * @param {string} key    R2 object key (path within bucket)
 * @param {string} contentType
 * @param {Object} ctx
 * @returns {Promise<Response>}
 */
async function serveR2Object(env, key, contentType, ctx) {
  /** @type {R2Object | null} */
  const obj = await env.PACKAGES_BUCKET.get(key);
  if (!obj) {
    return new Response(
      JSON.stringify({ error: 'Not Found', key }),
      {
        status: 404,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      }
    );
  }

  const headers = {
    ...CORS_HEADERS,
    'Content-Type': contentType,
    'ETag': obj.httpEtag,
    'Cache-Control': key.includes('latest-') ? 'public, max-age=60' : 'public, max-age=3600',
  };

  if (obj.size !== null) {
    headers['Content-Length'] = String(obj.size);
  }

  return new Response(obj.body, { status: 200, headers });
}

/**
 * Guess Content-Type from file extension.
 * @param {string} path
 * @returns {string}
 */
function guessContentType(path) {
  if (path.endsWith('.json')) return 'application/json';
  if (path.endsWith('.dmg')) return 'application/x-apple-diskimage';
  if (path.endsWith('.msi')) return 'application/x-msi';
  if (path.endsWith('.exe')) return 'application/vnd.microsoft.portable-executable';
  if (path.endsWith('.AppImage')) return 'application/x-executable';
  if (path.endsWith('.deb')) return 'application/vnd.debian.binary-package';
  if (path.endsWith('.rpm')) return 'application/x-rpm';
  if (path.endsWith('.tar.gz') || path.endsWith('.tgz')) return 'application/gzip';
  if (path.endsWith('.sig') || path.endsWith('.asc')) return 'text/plain';
  return 'application/octet-stream';
}
