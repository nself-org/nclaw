# nClaw Plugin Author Guide

nClaw v1.1.1 extends its capabilities through an **MCP-style plugin protocol** over HTTPS. Plugins run as independent servers in your nSelf deployment, and nClaw acts as an HTTP client discovering and invoking them.

## Overview

Every plugin exposes a standardized interface:
- **Tool Discovery:** `GET /mcp/tools` returns available functions as JSON-Schema definitions
- **Tool Invocation:** `POST /mcp/invoke` executes a tool and returns results (or streams NDJSON)
- **Authentication:** Bearer token passed in `Authorization` header
- **Rate Limiting:** Respect returned `X-RateLimit-*` headers

nClaw queries tool definitions at session start, caches them, and exposes them to the local LLM for intelligent tool-calling.

**Local plugin runtime is deferred to v1.2.x.** Current version requires plugins to run as self-hosted services in your nSelf deployment.

## Plugin Contract

### Tool Discovery Endpoint: `GET /mcp/tools`

Returns a JSON array of available tools. Example:

```json
[
  {
    "id": "send_email",
    "label": "Send Email",
    "description": "Send an email message",
    "input_schema": {
      "type": "object",
      "properties": {
        "to": {"type": "string", "description": "Recipient email address"},
        "subject": {"type": "string", "description": "Email subject"},
        "body": {"type": "string", "description": "Email body (HTML or plain text)"}
      },
      "required": ["to", "subject", "body"]
    },
    "streaming": false
  }
]
```

**Fields:**
- `id` — unique tool identifier (lowercase, hyphenated)
- `label` — human-readable name (show to user)
- `description` — what the tool does
- `input_schema` — JSON-Schema v7 describing input parameters
- `streaming` — if true, response body is line-delimited JSON (one result per line)

### Tool Invocation: `POST /mcp/invoke`

Request body:
```json
{
  "tool_id": "send_email",
  "args": {
    "to": "user@example.com",
    "subject": "Hello",
    "body": "Test message"
  }
}
```

Success response (200 OK):
```json
{
  "result": {
    "message_id": "msg_12345",
    "status": "sent"
  }
}
```

Streaming response (if `streaming: true` in tool definition):
```
{"result":{"step":"validating"}}
{"result":{"step":"sending"}}
{"result":{"step":"delivered"}}
```

Error response (non-2xx):
```json
{
  "error": {
    "code": "invalid_args",
    "message": "Missing required field: to",
    "retryable": false
  }
}
```

### Authentication

Every request includes:
```
Authorization: Bearer <license-and-tenant-token>
```

The token contains both the user's nSelf license and tenant ID. Plugins must validate the token and enforce per-tenant isolation.

### Rate Limiting

Plugins should return standard rate-limit headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1715123456
```

If rate-limited, return **429 Too Many Requests**:
```json
{
  "error": {
    "code": "rate_limited",
    "message": "Rate limit exceeded",
    "retryable": true
  }
}
```

## Error Contract

HTTP status + JSON body:

| Code | Meaning | `error.code` |
|------|---------|--------------|
| 200 | Success | (no error) |
| 400 | Invalid request | `invalid_args` |
| 401 | Auth failed | `unauthorized` |
| 404 | Tool not found | `not_found` |
| 429 | Rate limited | `rate_limited` |
| 502 | Upstream failed | `upstream_failed` |
| 500 | Internal error | `internal` |

Always include `retryable: boolean` to hint whether the client should retry.

## Security

- **Never pass keys to LLM context.** The LLM sees only the tool name, description, and input schema—not authentication headers.
- **Enforce per-tenant isolation.** Validate the token, extract tenant ID, and apply row-level security in your plugin's database queries.
- **Rate-limit per tenant.** Track usage by the bearer token to prevent one tenant from overwhelming your service.

## Local Development

1. **Write your plugin** (see hello-world example below):
   ```bash
   cd ~/my-plugin
   go run .
   ```
   Listens on `http://127.0.0.1:38XX` (choose an unused port in the 3800–3850 range).

2. **Configure nClaw dev settings:**
   Open nClaw settings → Plugin Overrides → add:
   ```
   http://localhost:38XX
   ```

3. **Restart nClaw** and tools should appear in the chat input autocomplete.

4. **Test with curl:**
   ```bash
   curl http://localhost:38XX/mcp/tools | jq
   curl -X POST http://localhost:38XX/mcp/invoke \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer test-token" \
     -d '{"tool_id":"echo","args":{"text":"Hello"}}'
   ```

## Reference Implementations

nSelf ships several canonical plugin implementations—use these as templates:

| Plugin | Language | Use Case |
|--------|----------|----------|
| **ai** | Go | LLM integration (Claude, GPT, Gemini) |
| **claw** | Go | Memory system (pgvector, tagging, search) |
| **mux** | Go | Email pipeline (parsing, classification) |
| **voice** | TypeScript | Voice transcription + synthesis |
| **browser** | Go | Web scraping + interaction |
| **google** | Go | Calendar, Gmail, Drive integration |
| **notify** | Go | Multi-channel notifications |
| **cron** | Go | Scheduled task execution |
| **claw-budget** | Go | Budget tracking with time-series data |
| **claw-news** | Go | News aggregation from feeds |
| **mcp** | Go | MCP server protocol adapter |
| **knowledge-base** | TypeScript | Document ingestion + semantic search |
| **claw-web** | TypeScript | Web UI for plugin configuration |

See the nSelf plugins-pro repository for full source code.

## Deployment

In production, your plugin runs as a service in the nSelf stack:

1. Build a Docker image (or use the Go binary directly)
2. Add it to your `docker-compose.yml` via `nself build` (custom service)
3. Configure firewall/Nginx to route `<hostname>/plugin/<your-plugin>` to the plugin's internal port
4. nClaw discovers it via service discovery at startup

Per the **nSelf-First Doctrine**, all plugins integrate via the nself CLI—no side-channel `docker-compose` modifications.

## What's Next?

- Check the hello-world example: `plugin-author-guide/examples/hello-world-plugin.md`
- Explore reference plugins in `plugins-pro/paid/` (private repo)
- Read the nClaw architecture docs for details on session lifecycle and tool-calling flow
