# Architecture Deep Dive

**Status:** Active

## Overview

ɳClaw is a multi-platform Flutter client that talks to a self-hosted nSelf backend. The backend runs three required pro plugins (`ai`, `claw`, `mux`) and several optional ones. A Rust FFI library (`libnclaw`) provides shared types, protocol definitions, and end-to-end encryption used across platforms.

This page explains how the layers fit together: the Flutter UI tree, state management, the libnclaw FFI bridge, the plugin protocol, the memory data model, the AI inference path, and the persistence layer.

For the per-AI-agent reference (used by automation), see `.claude/docs/ARCHITECTURE.md` in the repo. This wiki page is the public-facing version.

## Plugin source layout

The three required pro plugins live in the separate `plugins-pro/` repo (private, license-gated). Plugin source paths for internal reference:

- `plugins-pro/paid/ai/` — LLM gateway
- `plugins-pro/paid/claw/` — AI assistant core
- `plugins-pro/paid/mux/` — topic detection, content multiplexer

Plugin code is never bundled into this `claw/` repo. At backend install time, `nself license set ...` followed by `nself plugin install ai claw mux` pulls the plugin code into the user's `.backend/` directory.

## Requirements

| Item | Required | Notes |
|------|----------|-------|
| ɳSelf CLI | 1.0+ | F01-MASTER-VERSIONS |
| Plugin: `ai` | Yes | Pro tier — see [[plugin-ai]] in plugins-pro wiki |
| Plugin: `claw` | Yes | Pro tier — see [[plugin-claw]] in plugins-pro wiki |
| Plugin: `mux` | Yes | Pro tier — see [[plugin-mux]] in plugins-pro wiki |
| Service: PostgreSQL with pgvector + ltree | Yes | F08-SERVICE-INVENTORY |
| Service: Redis | Yes | F08-SERVICE-INVENTORY |
| Service: MinIO | Optional | for file uploads, voice recordings |
| Service: MeiliSearch | Optional | for full-text search |
| Tier (for required plugins) | Pro ($1.99/mo) | per F07-PRICING-TIERS |
| Bundle | ɳClaw Bundle | per F06-BUNDLE-INVENTORY |

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `CLAW_MEMORY_ENABLED` | `true` | Master switch for memory capture |
| `CLAW_MEMORY_TOPIC_DETECTION` | `true` | Auto-detect topics via mux |
| `CLAW_MEMORY_EMBEDDING_PROVIDER` | (per ai plugin) | Embedding provider for pgvector |
| `CLAW_E2E_ENABLED` | `false` | End-to-end encryption (per-device key) |

## Usage / Workflow

### Layered architecture

```
+------------------------------------------------------------+
|                    PRESENTATION LAYER                       |
|  Flutter app (app/) — iOS, Android, macOS, Web             |
|  Tauri desktop UI (apps/desktop/) — Linux, Windows, macOS  |
|  macOS menu-bar daemon (desktop/) — local HTTP port 7710   |
+------------------------------------------------------------+
                       |
                       v
+------------------------------------------------------------+
|                    STATE / LOGIC LAYER                      |
|  Riverpod providers — chat thread, persona, sidebar topics |
|  Service layer — network, FFI, persistence                 |
+------------------------------------------------------------+
                       |
                       v
+------------------------------------------------------------+
|                  SHARED FFI LAYER (libnclaw)                |
|  libs/libnclaw/ Rust crate (cdylib + staticlib)             |
|  Shared types, protocol, X25519 + XChaCha20-Poly1305       |
|  Bindings: dart:ffi (Dart), @_cdecl (Swift), JNI (Kotlin)  |
+------------------------------------------------------------+
                       |
                       v
+------------------------------------------------------------+
|                 TRANSPORT LAYER (HTTPS / WSS)               |
|  Hasura GraphQL: /v1/graphql (queries + mutations + subs)  |
|  nHost Auth: /v1/auth (JWT issue and refresh)               |
|  Plugin REST: /v1/plugins/<name> (voice, browser, mux)     |
+------------------------------------------------------------+
                       |
                       v
+------------------------------------------------------------+
|              nSELF BACKEND (separate plugins-pro repo)      |
|  ai plugin — LLM gateway, streaming                         |
|  claw plugin — memory, sessions, tool orchestration         |
|  mux plugin — topic detection, content multiplexing         |
|  Persistence: PostgreSQL (pgvector + ltree + JSONB) + Redis |
+------------------------------------------------------------+
```

### Sending a message

1. User types a message in the Flutter chat widget.
2. The widget calls `chatThreadProvider.send(text)` (Riverpod StateNotifier).
3. The provider invokes the chat service:
   a. If E2E is enabled, libnclaw FFI encrypts the text with the session key.
   b. The service POSTs a Hasura GraphQL mutation: `insert_np_claw_messages`.
4. Hasura inserts the row and triggers a webhook to the `claw` plugin.
5. The `claw` plugin loads thread context (Postgres + pgvector for relevant memory), calls `mux` for topic classification, and calls `ai` for the response.
6. `ai` streams response chunks. Each chunk is written to `np_claw_message_chunks`.
7. A Hasura subscription pushes each chunk to the Flutter app over WebSocket.
8. The Flutter `StreamProvider` rebuilds the chat widget per chunk. If E2E is on, libnclaw decrypts each chunk before render.
9. The final chunk closes the stream. `claw` writes the complete message and `mux` extracts facts, decisions, and entities into memory tables.

### Auto-topic detection

After each turn, `claw` posts the conversation to `mux`. `mux`:

- Calls `ai` to classify the topic (does this match an existing topic, or is it new?).
- Updates the `np_claw_topics` ltree path for the thread.
- Extracts facts (`np_claw_facts`), decisions (`np_claw_decisions`), and entities (`np_claw_entities`).

A Hasura subscription pushes the updated topic tree to the Flutter sidebar, which re-renders with auto-grouped topics. Conversations branch when the topic shifts mid-thread.

### Tool calls

When `ai` returns a `tool_call(name, args)`:

- `claw` identifies the tool and dispatches to the appropriate plugin or daemon:
  - `browser` plugin (Chrome DevTools Protocol commands)
  - `google` plugin (Gmail, Calendar, Drive)
  - `voice` plugin (TTS for spoken responses)
  - `mux` plugin (email pipeline actions)
  - macOS menu-bar daemon on `127.0.0.1:7710` (file access, shell exec, screenshot, clipboard)
- The tool result is appended to context.
- `ai` continues with the result and may chain another tool call.
- The final response streams back to the client.

## Limitations

- Native iOS (SwiftUI) and Android (Kotlin) apps are deferred. Flutter covers iOS, Android, macOS, and Web. See the libnclaw audit in `.claude/docs/libnclaw-audit.md` for the deferral decision.
- Web cannot use libnclaw FFI. Crypto operations on web use a WASM stub (preferred for E2E) or a REST proxy fallback (server briefly sees plaintext). See [[Web-Build-Guide]].
- Cross-device memory sync requires manual QR pairing or a short-code transfer. There is no implicit cloud sync.
- E2E key rotation requires re-pairing all devices and re-encrypting memory. There is no automated rotation flow.

### Known issues

None currently tracked.

## Troubleshooting

### Chat sends but no response streams

**Symptom:** Mutation succeeds but no streaming chunks arrive.
**Cause:** Hasura subscription connection failed (firewall blocking WebSocket, JWT expired).
**Fix:** Check browser DevTools Network tab for WSS connection. Refresh JWT (sign out, sign in). Verify firewall allows WSS to your backend.

### Topics don't appear in sidebar

**Symptom:** Conversations happen but the sidebar shows no topic tree.
**Cause:** `mux` plugin missing or `CLAW_MEMORY_TOPIC_DETECTION=false`.
**Fix:** `nself plugin install mux`. Verify env var. Restart the backend with `nself restart claw mux`.

### libnclaw symbol not found

**Symptom:** App crashes with "Failed to lookup symbol nclaw_*".
**Cause:** libnclaw was not built for the host platform, or the export is missing.
**Fix:** Rebuild libnclaw per the platform's build guide. See [[libnclaw-Dev-Guide]].

## Related

- [[AI-Chat]] — feature page for chat
- [[Memory]] — feature page for the memory system
- [[Personas]] — feature page for personas
- [[Tool-Calls]] — feature page for tool execution
- [[E2E-Encryption]] — feature page for end-to-end encryption
- [[libnclaw-Dev-Guide]] — work on the FFI library
- [[Architecture]] — original component overview
- [[Features]] — full feature index

← [[Features]] | [[Home]] →
