# Architecture

## Component Overview

```
+--------------------------------------------------+
|                  Client Layer                    |
|                                                  |
|  +------------+  +----------+  +-------------+  |
|  | Flutter app|  | SwiftUI  |  | Kotlin app  |  |
|  |  (app/)    |  | (apps/   |  | (apps/      |  |
|  | iOS/Android|  |  ios/)   |  |  android/)  |  |
|  | macOS/web  |  |          |  |             |  |
|  +-----+------+  +----+-----+  +------+------+  |
|        |              |               |          |
+--------+------+-------+------+--------+---------+
                |              |
         +------+--------------+------+
         |         libnclaw           |
         |   (libs/libnclaw/ — Rust)  |
         |                            |
         |  - Shared types            |
         |  - Protocol definitions    |
         |  - E2E encryption          |
         |    (X25519 + XChaCha20-    |
         |     Poly1305)              |
         |  - FFI bindings for        |
         |    Swift, Kotlin, Dart     |
         +-------------+--------------+
                       |
              HTTP / WebSocket
                       |
         +-------------+--------------+
         |      nSelf Backend          |
         |                            |
         |  PostgreSQL                |
         |  Hasura GraphQL API        |
         |  nHost Auth                |
         |  MinIO Storage             |
         |  Nginx (reverse proxy)     |
         |                            |
         |  Pro Plugins:              |
         |    nself-ai                |
         |    nself-claw              |
         |    nself-mux               |
         |    nself-voice             |
         |    nself-browser           |
         +----------------------------+
```

---

## FFI Layer (libnclaw)

`libs/libnclaw/` is a Rust library that serves as the single source of truth for:

- **Types** — All shared data types (messages, threads, personas, tool calls, etc.)
- **Protocol** — Wire format for communication between clients and backend
- **E2E encryption** — X25519 key exchange + XChaCha20-Poly1305 authenticated encryption

Clients consume libnclaw via platform FFI:

| Platform | Binding mechanism |
|----------|------------------|
| Flutter (Dart) | `dart:ffi` + generated bindings |
| SwiftUI (iOS/macOS) | Swift Package / `@_cdecl` C ABI |
| Kotlin (Android) | JNI via Rust `jni` crate |

**Rule:** Do not duplicate type definitions in client code. If a type belongs to the protocol, it lives in libnclaw.

---

## Backend Integration

The nSelf backend exposes:

| Endpoint | URL | Purpose |
|----------|-----|---------|
| GraphQL API | `/v1/graphql` | All data queries and mutations |
| GraphQL subscriptions | `/v1/graphql` (WebSocket) | Real-time updates |
| Auth | `/v1/auth` | Sign-in, token refresh, user management |
| Storage | `/v1/storage` | File uploads and downloads |
| Plugin REST APIs | `/v1/plugins/<name>` | Plugin-specific endpoints (voice, browser, etc.) |

Authentication uses JWT tokens issued by nHost Auth. Clients include the token in the `Authorization: Bearer <token>` header for all requests.

---

## Data Flow

### Sending a message

```
User types message
  → Flutter UI captures input
  → libnclaw serializes message (applies E2E encryption if enabled)
  → HTTP POST to Hasura GraphQL mutation
  → nself-claw plugin processes message
  → nself-ai plugin routes to AI provider
  → Response streams back via GraphQL subscription
  → libnclaw decrypts and deserializes
  → Flutter UI renders response
```

### Tool call execution

```
AI response contains tool call
  → nself-claw plugin identifies tool
  → Dispatches to appropriate plugin:
      web search  → nself-mux
      browser     → nself-browser
      voice       → nself-voice
  → Tool result appended to context
  → AI continues with tool result
  → Final response returned to client
```

### Voice input

```
User speaks
  → Native platform captures audio
  → Audio stream sent to nself-voice plugin
  → Speech-to-text transcription returned
  → Transcription injected into message input
  → Normal message flow continues
```

---

## Repo Structure

```
app/              Flutter client (iOS, Android, macOS, web)
apps/
  ios/            SwiftUI native client (iOS + macOS)
  android/        Kotlin + Jetpack Compose native client
  desktop/        Tauri desktop companion
libs/
  libnclaw/       Shared Rust FFI library
backend/          nSelf backend config for self-hosters
```

---

## Security Model

- All data in transit uses TLS (enforced by nSelf Nginx)
- Optional E2E encryption via libnclaw (X25519 + XChaCha20-Poly1305) encrypts message content before it leaves the device
- No hardcoded server URLs — clients connect to user-configured backend addresses
- Secrets (JWT, admin keys) never leave the backend; clients only hold short-lived access tokens
