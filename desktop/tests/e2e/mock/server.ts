/**
 * Mock backend stub server for nclaw e2e tests (T08/T09/T10).
 * Stubs the nclaw client's required endpoints with deterministic responses.
 * No real backend required — hermetic Playwright fixture.
 */

import * as http from 'http';
import * as net from 'net';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const TOPICS_FIXTURE = [
  { id: 'topic-1', name: 'General', created_at: '2024-01-01T00:00:00Z' },
  { id: 'topic-2', name: 'Work', created_at: '2024-01-02T00:00:00Z' },
];

const SETTINGS_FIXTURE = {
  theme: 'dark',
  language: 'en',
  notifications: true,
};

// ---------------------------------------------------------------------------
// Port helpers
// ---------------------------------------------------------------------------

function probePort(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const probe = net.createServer();
    probe.once('error', () => resolve(false));
    probe.once('listening', () => {
      probe.close(() => resolve(true));
    });
    probe.listen(port, '127.0.0.1');
  });
}

async function findFreePort(start: number): Promise<number> {
  for (let p = start; p < start + 20; p++) {
    if (await probePort(p)) return p;
  }
  throw new Error(`No free port found starting from ${start}`);
}

// ---------------------------------------------------------------------------
// Route handler
// ---------------------------------------------------------------------------

function handleRequest(
  req: http.IncomingMessage,
  res: http.ServerResponse,
): void {
  const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
  const method = req.method ?? 'GET';
  const pathname = url.pathname;

  // POST /api/chat/stream — SSE streaming response
  if (method === 'POST' && pathname === '/api/chat/stream') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });

    const chunks = [
      'data: {"chunk":"Hello"}\n\n',
      'data: {"chunk":" world"}\n\n',
      'data: [DONE]\n\n',
    ];

    let i = 0;
    const interval = setInterval(() => {
      if (i < chunks.length) {
        res.write(chunks[i]);
        i++;
      } else {
        clearInterval(interval);
        res.end();
      }
    }, 10);
    return;
  }

  // GET /api/topics
  if (method === 'GET' && pathname === '/api/topics') {
    const body = JSON.stringify(TOPICS_FIXTURE);
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(body);
    return;
  }

  // POST /api/topics
  if (method === 'POST' && pathname === '/api/topics') {
    const newTopic = {
      id: `topic-${Date.now()}`,
      name: 'New Topic',
      created_at: new Date().toISOString(),
    };
    res.writeHead(201, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify(newTopic));
    return;
  }

  // DELETE /api/topics/:id
  if (method === 'DELETE' && /^\/api\/topics\/[^/]+$/.test(pathname)) {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*' });
    res.end();
    return;
  }

  // GET /api/settings
  if (method === 'GET' && pathname === '/api/settings') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify(SETTINGS_FIXTURE));
    return;
  }

  // POST /api/settings
  if (method === 'POST' && pathname === '/api/settings') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  // OPTIONS preflight (CORS)
  if (method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    });
    res.end();
    return;
  }

  // GET / — health check (Playwright webServer polls this before running tests)
  if (method === 'GET' && pathname === '/') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  // 404 fallback
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found', path: pathname }));
}

// ---------------------------------------------------------------------------
// Server lifecycle
// ---------------------------------------------------------------------------

let activeServer: http.Server | null = null;

export async function startServer(port?: number): Promise<number> {
  const defaultPort = parseInt(process.env.MOCK_PORT ?? '5174', 10);
  const targetPort = port ?? defaultPort;
  const resolvedPort = await findFreePort(targetPort);

  return new Promise((resolve, reject) => {
    const server = http.createServer(handleRequest);

    server.once('error', reject);
    server.listen(resolvedPort, '127.0.0.1', () => {
      activeServer = server;
      resolve(resolvedPort);
    });
  });
}

export function stopServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    if (!activeServer) {
      resolve();
      return;
    }
    activeServer.close((err) => {
      activeServer = null;
      if (err) reject(err);
      else resolve();
    });
  });
}

// ---------------------------------------------------------------------------
// Standalone entrypoint (invoked by Playwright webServer config)
// ---------------------------------------------------------------------------

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = parseInt(process.env.MOCK_PORT ?? '5174', 10);
  startServer(port).then((bound) => {
    console.log(`Mock server listening on http://127.0.0.1:${bound}`);
  }).catch((err: unknown) => {
    console.error('Failed to start mock server:', err);
    process.exit(1);
  });
}
