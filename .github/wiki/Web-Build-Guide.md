# Build ɳClaw for Web

By the end of this guide you will:

- Have ɳClaw running in a browser as a Flutter web app.
- Understand the WASM / REST proxy fallback for libnclaw on web (FFI is not available in browsers).

## Prerequisites

- Flutter 3.x (`flutter --version`) with web support enabled (`flutter config --enable-web`).
- A modern browser (Chrome, Edge, Firefox, Safari recent versions).
- A static host for deployment (Vercel, Netlify, Cloudflare Pages, nginx, S3+CloudFront).
- Your nSelf backend reachable from the browser (CORS configured on Hasura, plugin REST endpoints).

## libnclaw on web — important note

Flutter web compiles to JavaScript. There is no FFI on web — the native Rust `libnclaw` library cannot be linked. ɳClaw web has two options:

1. **WASM stub** (preferred): compile a subset of libnclaw to WebAssembly and call it from Dart via `package:wasm` or `dart:js_interop`. Works for crypto operations but adds bundle size.
2. **REST proxy fallback**: encryption operations call the backend `claw` plugin REST endpoint (which uses server-side libnclaw). Simpler, no WASM, but the backend sees plaintext briefly during encryption.

For E2E encryption requirements (D-003), the WASM stub is the only path that keeps the server from seeing plaintext. For non-E2E deployments, the REST fallback is acceptable.

## Steps

### Step 1 — Install Flutter dependencies

```bash
cd claw/app
flutter pub get
```

### Step 2 — Choose a renderer

```bash
# CanvasKit — better fidelity, larger bundle (~2MB extra)
flutter build web --web-renderer canvaskit --release

# HTML — smaller bundle, less fidelity (text/SVG layout differs slightly)
flutter build web --web-renderer html --release
```

Default and recommended: CanvasKit. Use HTML only when bundle size is critical.

Expected output:

```
Built build/web (xx.xMB)
```

### Step 3 — Configure CSP (Content Security Policy)

Edit `app/web/index.html` and add a CSP meta tag that allows your backend origin:

```html
<meta http-equiv="Content-Security-Policy" content="
  default-src 'self';
  connect-src 'self' https://api.your-backend.com wss://api.your-backend.com;
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https:;
  font-src 'self' data:;
">
```

Replace `https://api.your-backend.com` with the URL of your nSelf backend. The `connect-src` directive must include both HTTPS (for queries / mutations) and WSS (for subscriptions).

### Step 4 — Configure PWA manifest (optional)

Edit `app/web/manifest.json` to enable Progressive Web App install:

```json
{
  "name": "ɳClaw",
  "short_name": "Claw",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#0F0F1A",
  "theme_color": "#0EA5E9",
  "icons": [
    {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png"}
  ]
}
```

Browsers will prompt to install ɳClaw to the home screen / app launcher.

### Step 5 — Deploy to a static host

For Vercel:

```bash
# From repo root
vercel --prod ./build/web
```

For Cloudflare Pages:

```bash
wrangler pages deploy build/web --project-name=nclaw-web
```

For nginx:

```nginx
server {
  listen 443 ssl http2;
  server_name claw.example.com;

  root /var/www/nclaw/build/web;
  index index.html;

  location / {
    try_files $uri $uri/ /index.html;
  }
}
```

### Step 6 — Configure backend CORS

For the web build to reach Hasura and plugin REST endpoints, configure CORS on the backend. In `nself.env` (or the equivalent):

```
HASURA_GRAPHQL_CORS_DOMAIN=https://claw.example.com
```

Restart the backend:

```bash
nself restart hasura
```

## Verification

Open the deployed URL in a browser. Expected behavior:

- App shell loads (no console errors about CSP or CORS).
- Onboarding starts (enter your backend URL).
- Sign in works (auth via nHost Auth).
- Chat sends and streams a response.
- Browser DevTools Network tab shows GraphQL queries to your backend, no CORS errors.

For the WASM stub path (if enabled): DevTools > Network shows a `.wasm` file loaded once at startup.

For the REST fallback path: encryption operations show as POST requests to `/v1/plugins/claw/encrypt` (or similar).

## Troubleshooting

### "Refused to connect to ... due to CSP directive"

**Symptom:** Browser console blocks WebSocket / fetch with a CSP violation.
**Cause:** Backend origin is not in the CSP `connect-src` list.
**Fix:** Edit `index.html` to include your backend HTTPS and WSS URLs in `connect-src`.

### "CORS policy: No 'Access-Control-Allow-Origin' header"

**Symptom:** Browser blocks Hasura requests with a CORS error.
**Cause:** `HASURA_GRAPHQL_CORS_DOMAIN` does not include the web origin.
**Fix:** Set `HASURA_GRAPHQL_CORS_DOMAIN=https://your-web-origin` in the backend env, restart Hasura.

### libnclaw call fails on web

**Symptom:** Crypto operations throw `LibnclawNotAvailableException`.
**Cause:** libnclaw FFI is not available on web. The app must use the WASM stub or REST proxy fallback.
**Fix:** Configure the app to use the WASM build (or accept the REST fallback). Verify the WASM file is loaded in DevTools > Network.

### PWA install prompt does not appear

**Symptom:** "Install" option is missing in the browser menu.
**Cause:** Manifest is malformed, or service worker is not registered.
**Fix:** Run Lighthouse PWA audit in Chrome DevTools. Common fixes: ensure `manifest.json` is reachable, icons exist at the listed sizes, the page is served over HTTPS.

## Next Steps

- [[macOS-Build-Guide]] — build for macOS
- [[Desktop-Build-Guide]] — build for Linux + Windows desktop
- [[E2E-Encryption]] — feature page (covers WASM vs REST tradeoff)
- [[Troubleshooting]] — common errors across platforms

← [[Home]] | [[Home]] →
