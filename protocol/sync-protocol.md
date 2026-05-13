# nClaw Sync Protocol — v1 Specification

**Version:** 1.0  
**Status:** Canonical design spec (P101 S17.T01)  
**Audience:** Server implementors (plugins-pro/nself-sync), client implementors (desktop/, mobile/, core/)  
**Cross-refs:** Decision #5 (event-log + LWW + Hasura subscriptions), Decision #7 (conversation auto-topics via mux), Decision #10 (server-of-record)  

---

## 1. Overview

ɳClaw is a personal AI assistant built on the principle that your data belongs to you. Users run the nSelf backend on their own infrastructure — a Hetzner VPS, a local machine, or anywhere Docker runs. The sync protocol is what makes that backend feel like a cloud product: changes made on your phone appear instantly on your desktop. Changes made offline catch up the moment you reconnect. Two devices editing the same conversation entry at the same moment converge to a predictable, correct result.

### 1.1 Core Design Goals

**Local-first operation.** Every client maintains a local cache of all data it has ever fetched. Reads never block on the network. Writes go to the local cache immediately and propagate to the server asynchronously. The UI is always responsive.

**Eventual consistency.** The system converges: given enough time and connectivity, all devices that share a user account reach the same state. There is no coordination required before writing. Divergence is expected and resolved deterministically.

**Server-of-record (Decision #10).** The server holds the authoritative, durable copy of all events. Clients are caches. A client that has been offline for a month can always pull the events it missed from the server and reconstruct current state. The server never discards events within the retention window (90 days for tombstones, indefinite for live data).

**Event-log model (Decision #5).** The system stores every change as an immutable event rather than mutating rows in place. This gives us a complete audit trail, reproducible state at any point in history, and a natural mechanism for multi-device replication: clients exchange event lists rather than row snapshots.

**Hybrid logical clock ordering.** Clocks on different devices drift. Wall clocks alone cannot order events from multiple devices consistently. The protocol uses a Hybrid Logical Clock (HLC) that combines wall time with a logical counter, giving total event ordering that respects causality even across clock-skewed devices.

**Hasura subscriptions for push (Decision #5).** Rather than polling, clients subscribe to new events over a persistent WebSocket managed by Hasura GraphQL subscriptions. The server pushes events to all connected devices the moment they land. Offline clients miss push events; they catch up via pull on reconnect.

### 1.2 What This Document Covers

This document is the canonical specification for:

- The shape and semantics of every sync event (the "event envelope")
- The Hybrid Logical Clock algorithm and its tie-breaking rules
- The Last-Write-Wins (LWW) conflict resolution strategy
- The wire format for events on the network
- The five message types clients and servers exchange
- How devices authenticate and bind their identity to events
- The versioning policy for this protocol
- Bandwidth and compression strategies
- Three fully worked end-to-end examples
- Error contracts and retry semantics
- Failure modes and how the system handles each

This document does not cover the nSelf backend setup, the ɳClaw bundle plugin configuration, or the Hasura schema DDL. Those live in the backend and plugins-pro repos respectively.

### 1.3 Relationship to Other Protocol Docs

```
protocol/
├── sync-protocol.md     ← this document
├── vault-protocol.md    (planned — E2E key exchange and device pairing)
└── plugin-mcp-protocol.md  (planned — MCP tool call protocol)
```

The sync protocol is agnostic to E2E encryption. When E2E is enabled (the default, per Decision #3), the `payload` field inside each event is an XChaCha20-Poly1305 ciphertext. The sync layer treats it as opaque bytes. Key exchange and device pairing live in the vault protocol.

---

## 2. Event Envelope

Every mutation in ɳClaw is expressed as an event. Events are immutable once written. They are never updated or deleted in place; a correction is itself a new event.

### 2.1 Canonical Schema

```json
{
  "event_id": "0193b6c0-7e7f-7000-8000-000000000001",
  "entity_type": "message",
  "entity_id": "018f2a1b-0000-7000-8000-000000000042",
  "op": "insert",
  "timestamp": {
    "wall_ms": 1715626800000,
    "lamport": 17,
    "device_id": "018e9c3f-0000-7000-8000-0000000000ab"
  },
  "user_id": "018d4a2e-0000-7000-8000-000000000001",
  "device_id": "018e9c3f-0000-7000-8000-0000000000ab",
  "tenant_id": null,
  "payload": {
    "conversation_id": "018f2a1b-0000-7000-8000-000000000011",
    "role": "user",
    "content": "What did I decide about the project proposal?",
    "topic_ids": ["018f1a00-0000-7000-8000-000000000099"],
    "created_at": "2024-05-13T19:00:00Z"
  },
  "schema_version": 1,
  "signature": "base64url-encoded-ed25519-signature"
}
```

### 2.2 Field Reference

| Field | Type | Required | Notes |
|---|---|---|---|
| `event_id` | UUID v7 | Yes | Time-sortable. Generated by the originating client. Globally unique. |
| `entity_type` | string | Yes | One of: `message`, `conversation`, `topic`, `memory_fact`, `persona`, `tool_result`, `presence`. Max 64 chars. |
| `entity_id` | UUID v7 | Yes | The ID of the entity being mutated. Stable across all events for the same entity. |
| `op` | enum | Yes | `insert`, `update`, or `delete`. |
| `timestamp.wall_ms` | int64 | Yes | Unix milliseconds at time of event creation. See HLC section. |
| `timestamp.lamport` | uint32 | Yes | HLC logical counter. Starts at 0. Rolls over at 2^32 − 1 (rare; treat as monotone). |
| `timestamp.device_id` | UUID v7 | Yes | Device that originated this event. Matches top-level `device_id`. |
| `user_id` | UUID v7 | Yes | The nHost Auth user who owns this event. |
| `device_id` | UUID v7 | Yes | The registered device that created the event. Must match registered pubkey on the server. |
| `tenant_id` | UUID v4 or null | No | Null for self-hosted single-tenant. UUID for nSelf Cloud multi-tenant deployments. Hasura row filter enforces isolation when non-null. |
| `payload` | object or null | Conditional | Null for `delete` ops. Full row snapshot for `insert`. Field deltas only for `update` (include only changed fields). |
| `schema_version` | int | Yes | Protocol schema version. Currently `1`. |
| `signature` | string | Yes | Base64url-encoded Ed25519 signature of the canonical serialisation of all other fields. |

### 2.3 Size Budget

- `event_id`: 16 bytes (UUID binary)
- `entity_id`: 16 bytes
- `device_id`: 16 bytes
- `user_id`: 16 bytes
- `tenant_id`: 16 bytes or 0 (null)
- All fixed header fields: ~128 bytes
- `payload`: target ≤16 KB, hard limit 64 KB

If a payload exceeds 64 KB, the client splits it into a sequence of chunk events. Each chunk carries the same `entity_id` and a `chunk_sequence` field in its payload (0-indexed). The receiver reassembles chunks in sequence order before processing. A partial chunk set is held in a pending-reassembly buffer. After 24 hours without the remaining chunks, the buffer is discarded and the event is logged as `INCOMPLETE`.

### 2.4 Entity Types and Their Payloads

**`message`** — a single turn in a conversation:
```json
{
  "conversation_id": "uuid",
  "role": "user" | "assistant" | "tool",
  "content": "string (plaintext or ciphertext)",
  "tool_call_id": "string | null",
  "topic_ids": ["uuid"],
  "model": "string | null",
  "token_count": 0,
  "created_at": "ISO8601"
}
```

**`conversation`** — metadata for a conversation branch:
```json
{
  "title": "string",
  "persona_id": "uuid | null",
  "parent_topic_id": "uuid | null",
  "archived": false,
  "pinned": false
}
```

**`topic`** — an auto-detected or user-created topic (Decision #7):
```json
{
  "label": "string",
  "path": "ltree path string e.g. work.projects.proposal",
  "parent_id": "uuid | null",
  "auto_detected": true,
  "confidence": 0.95
}
```

**`memory_fact`** — an extracted fact stored in pgvector:
```json
{
  "text": "string",
  "embedding_model": "text-embedding-3-small",
  "vector": [0.12, -0.34, ...],
  "source_message_id": "uuid | null",
  "confidence": 0.87,
  "tags": ["decision", "project"]
}
```

**`persona`** — a custom AI persona:
```json
{
  "name": "string",
  "system_prompt": "string",
  "model_preference": "string | null",
  "avatar_url": "string | null"
}
```

---

## 3. Hybrid Logical Clock

Standard wall clocks differ across devices. Network Time Protocol keeps them close but not identical — skews of hundreds of milliseconds are common; skews of several seconds happen in practice. If device A creates an event at wall clock T=1000 and device B creates an event at T=999 (due to clock skew), a naive wall-clock sort puts B before A even though A happened first in real time.

The Hybrid Logical Clock (HLC) solves this by augmenting wall time with a logical counter that advances monotonically. It guarantees: if event A causally precedes event B (A was sent and received before B was created), then HLC(A) < HLC(B). It also stays close to wall time so timestamps remain human-readable.

### 3.1 State Per Device

Each device maintains:

```
hlc.wall_ms   int64    // latest wall time seen (local or received)
hlc.lamport   uint32   // logical counter
hlc.device_id uuid     // this device's ID (stable)
```

### 3.2 Tick Rules

**When creating a new event:**

```
now = current_wall_time_ms()
if now > hlc.wall_ms:
    hlc.wall_ms = now
    hlc.lamport = 0
else:
    hlc.lamport = hlc.lamport + 1
event.timestamp = { wall_ms: hlc.wall_ms, lamport: hlc.lamport, device_id: hlc.device_id }
```

**When receiving an event from another device:**

```
recv_wall = event.timestamp.wall_ms
recv_lamport = event.timestamp.lamport
now = current_wall_time_ms()

new_wall = max(hlc.wall_ms, recv_wall, now)
if new_wall == hlc.wall_ms and new_wall == recv_wall:
    hlc.lamport = max(hlc.lamport, recv_lamport) + 1
elif new_wall == hlc.wall_ms:
    hlc.lamport = hlc.lamport + 1
elif new_wall == recv_wall:
    hlc.lamport = recv_lamport + 1
else:
    hlc.lamport = 0
hlc.wall_ms = new_wall
```

This is the Kulkarni-Demirbas HLC algorithm. The device updates its clock state before it processes the received event, so any events it creates in response carry an HLC strictly greater than the received event's HLC.

### 3.3 Total Order (Tie-breaking)

To compare two HLC timestamps `A` and `B`:

1. If `A.wall_ms != B.wall_ms`: the earlier wall_ms is first.
2. If `A.wall_ms == B.wall_ms` and `A.lamport != B.lamport`: the lower lamport is first.
3. If both are equal: compare `device_id` lexicographically (ASCII byte order). The lexicographically earlier device_id is first.

This gives a strict total order. Two events from different devices can share wall_ms and lamport only if they were created truly concurrently on devices with the same clock state — the device_id tiebreak makes the order deterministic, even if arbitrary.

### 3.4 Server Timestamp Authority

The server records the time each event is received in a `server_received_ms` field in the event log table. This timestamp is not part of the sync event envelope that clients sign, but it is used by the server in one case: when two events arrive with identical HLC timestamps (all three fields equal), the server uses `server_received_ms` as the final tiebreaker. This is an extremely rare edge case — identical HLCs require the same wall_ms, same lamport counter, and identical device_id (which means the same device, which means the events are duplicates, handled by idempotency).

### 3.5 Clock Skew Handling

If a client's `wall_ms` in an event is more than 30 seconds ahead of the server's wall clock, the server rejects the event with error `CLOCK_SKEW_TOO_LARGE`. The client should sync its system clock and retry. The error includes the server's current wall time so the client can self-correct.

If a client's `wall_ms` is in the past (behind the server), it is accepted. The server's HLC advances to at least the event's wall_ms during ingestion.

---

## 4. LWW Conflict Resolution

Last-Write-Wins means: when two versions of the same entity exist, the one with the larger HLC timestamp wins. The losers are discarded (for `update` ops) or ignored (for conflicting `delete` vs `update`).

### 4.1 Per-Entity Resolution

The server and every client maintain a per-entity "current head" in their local state. The head is the event with the largest HLC timestamp for a given `(entity_type, entity_id)` pair.

When a new event arrives for an entity:

1. Compare the event's `timestamp` against the current head's `timestamp` using the total order from §3.3.
2. If the new event is later: it becomes the new head.
3. If the new event is earlier: it is a late-arriving event. Apply it to the event log for history, but do not update the current state snapshot.

### 4.2 Per-Field LWW for Update Operations

An `update` event carries only the fields that changed in its `payload`. This is important: it means two devices can update different fields of the same entity concurrently without conflicting.

Example: device A changes `conversation.title` offline. Device B changes `conversation.pinned` offline. Both update events arrive at the server.

Resolution: apply both. Title comes from A's event (or B's, depending on HLC order). Pinned comes from B's event. No fields are lost. The merged state has the later title and the later pinned value — which in this case are from different events, and that is correct.

Per-field LWW requires the server to maintain a per-field HLC tracking structure, not just a per-entity one. The implementation stores this in the `np_sync_field_heads` table:

```
entity_type  string
entity_id    uuid
field_name   string
hlc_wall_ms  int64
hlc_lamport  uint32
hlc_device   uuid
value_json   jsonb   -- the winning field value
```

### 4.3 Tombstones (Delete Semantics)

A `delete` event creates a tombstone for `(entity_type, entity_id)`. The tombstone wins over any `insert` or `update` with an older HLC. Concretely:

- If a `delete` arrives after an `insert`/`update`: tombstone wins. The entity is marked deleted. Subsequent `update` events with older HLCs are ignored.
- If an `insert`/`update` arrives after a `delete` with an older HLC: the newer write wins. The tombstone is cleared. The entity is restored.
- If two `delete` events arrive for the same entity: idempotent. The entity stays deleted.

Tombstones are retained for 90 days from the time of the `delete` event. A daily vacuum job removes tombstones older than 90 days. After removal, a late-arriving event for the same entity is treated as an `insert`.

### 4.4 Idempotency

Every event has a globally unique `event_id` (UUID v7). The server tracks all ingested event IDs in the `np_sync_event_log` table. If a client pushes an event that the server has already seen (same `event_id`), the server returns a success ack with status `DUPLICATE` rather than reprocessing it. Clients use this to safely retry pushes after network failures.

---

## 5. Wire Format

### 5.1 Primary Format: Protocol Buffers

The canonical wire format is Protocol Buffers (proto3). It is binary, compact, and efficient. Every client and server implementation must support proto3 as the primary format.

The full `.proto` schema for the sync protocol:

```proto
syntax = "proto3";
package nclaw.sync.v1;
option go_package = "github.com/nself-org/nself-sync/syncv1";

// HybridLogicalClock carries wall time, logical counter, and device origin.
message HybridLogicalClock {
  int64  wall_ms   = 1;
  uint32 lamport   = 2;
  bytes  device_id = 3; // UUID v7, 16 bytes big-endian
}

// Event is the atomic unit of replication.
message Event {
  bytes               event_id       = 1;  // UUID v7, 16 bytes
  string              entity_type    = 2;  // max 64 chars
  bytes               entity_id      = 3;  // UUID v7, 16 bytes
  Op                  op             = 4;
  HybridLogicalClock  timestamp      = 5;
  bytes               user_id        = 6;  // UUID v7, 16 bytes
  bytes               device_id      = 7;  // UUID v7, 16 bytes
  bytes               tenant_id      = 8;  // UUID v4, 16 bytes; empty = null
  bytes               payload        = 9;  // JSON-encoded or ciphertext; empty = null for delete
  uint32              schema_version = 10; // currently 1
  bytes               signature      = 11; // Ed25519 signature, 64 bytes
}

enum Op {
  OP_UNSPECIFIED = 0;
  OP_INSERT      = 1;
  OP_UPDATE      = 2;
  OP_DELETE      = 3;
}

// EventAck acknowledges a single event after server ingestion.
message EventAck {
  bytes  event_id          = 1;
  Status status            = 2;
  string error_message     = 3; // non-empty on ERROR status
  int64  server_ingested_ms = 4; // server wall time at ingestion
}

enum Status {
  STATUS_UNSPECIFIED = 0;
  STATUS_OK          = 1;
  STATUS_DUPLICATE   = 2; // already ingested; success
  STATUS_ERROR       = 3;
  STATUS_SCHEMA_ERROR = 4; // schema_version not supported; client must upgrade
  STATUS_CLOCK_SKEW  = 5; // wall_ms too far ahead; see ClockSkewError
}

// PushRequest sends a batch of events from a client to the server.
message PushRequest {
  repeated Event events = 1; // max 500 events per request; split larger batches
}

// PushResponse returns per-event acks.
message PushResponse {
  repeated EventAck acks = 1;
}

// PullRequest asks the server for events since a given HLC cursor.
message PullRequest {
  HybridLogicalClock since         = 1; // exclusive lower bound; zero-value = from beginning
  repeated string    entity_types  = 2; // filter to these types; empty = all types
  uint32             limit         = 3; // max events to return; default 500; max 2000
  string             cursor        = 4; // opaque pagination cursor from previous PullResponse
}

// PullResponse returns a page of events and a continuation cursor.
message PullResponse {
  repeated Event events    = 1;
  bool           has_more  = 2;
  string         cursor    = 3; // pass back in next PullRequest.cursor to continue
}

// SnapshotRequest asks for a full entity snapshot for new-device bootstrap.
message SnapshotRequest {
  repeated string entity_types = 1; // empty = all types
  bytes           tenant_id    = 2; // optional multi-tenant filter
}

// SnapshotResponse is a paginated stream of events representing current state.
message SnapshotResponse {
  repeated Event events       = 1;
  bool           has_more     = 2;
  string         cursor       = 3;
  int64          snapshot_at_ms = 4; // server wall time at snapshot start
}

// ClockSkewError is returned as error detail when STATUS_CLOCK_SKEW is set.
message ClockSkewError {
  int64 server_wall_ms = 1; // server's current wall time
  int64 client_wall_ms = 2; // the offending client timestamp
  int64 skew_ms        = 3; // abs(client - server)
}

// SubscribeRequest opens a WebSocket subscription for real-time event push.
message SubscribeRequest {
  HybridLogicalClock since        = 1; // receive events with HLC > since
  repeated string    entity_types = 2; // filter; empty = all
}

// HeartbeatRequest / HeartbeatResponse keep the WebSocket alive.
message HeartbeatRequest {
  int64 client_wall_ms = 1;
}
message HeartbeatResponse {
  int64 server_wall_ms = 1;
}
```

### 5.2 JSON Fallback

For debugging and environments where protobuf tooling is unavailable (browser WebAssembly without protobuf support, curl-based testing), the server accepts and returns JSON. Clients signal their preference via the `Content-Type` header:

- `application/x-protobuf` — proto3 binary (default)
- `application/json` — JSON encoding

In JSON mode, UUID fields are hex strings with hyphens (e.g., `"018f2a1b-0000-7000-8000-000000000042"`). Byte fields that are not UUIDs (signature, payload) are base64url-encoded. HLC timestamps use an object with `wall_ms`, `lamport`, and `device_id` keys.

Production deployments should always use proto3. JSON mode is explicitly for developer tooling.

---

## 6. Message Types

### 6.1 PushEvents — POST /sync/push

Clients send buffered local events to the server. The server validates, deduplicates, and broadcasts to other subscribed devices.

**Request:** `PushRequest` (proto3 or JSON)

**Headers required:**
```
Authorization: Bearer <nhost-jwt>
X-NClaw-Sync-Version: 1
X-NClaw-Device-Id: <device-uuid>
Content-Type: application/x-protobuf
```

**Response:** `PushResponse`

**Behavior:**
- Events are ingested atomically per event (not per batch). A batch of 10 events where event 5 fails returns acks 1-4 as OK and event 5 as ERROR; events 6-10 are still attempted.
- Max 500 events per request. If a client has more, it splits into sequential push calls.
- The server updates the Hasura event log table, which triggers subscriptions on other connected devices.

**Example push (single message insert, JSON mode for readability):**

```json
POST /sync/push HTTP/1.1
Content-Type: application/json
X-NClaw-Sync-Version: 1

{
  "events": [{
    "event_id": "0193b6c0-7e7f-7000-8000-000000000001",
    "entity_type": "message",
    "entity_id": "018f2a1b-0000-7000-8000-000000000042",
    "op": "insert",
    "timestamp": { "wall_ms": 1715626800000, "lamport": 17, "device_id": "018e9c3f-0000-7000-8000-0000000000ab" },
    "user_id": "018d4a2e-0000-7000-8000-000000000001",
    "device_id": "018e9c3f-0000-7000-8000-0000000000ab",
    "tenant_id": null,
    "payload": { "conversation_id": "018f2a1b-0000-7000-8000-000000000011", "role": "user", "content": "What did I decide about the proposal?", "topic_ids": [], "created_at": "2024-05-13T19:00:00Z" },
    "schema_version": 1,
    "signature": "MEUCIQDj..."
  }]
}
```

**Response:**
```json
{
  "acks": [{
    "event_id": "0193b6c0-7e7f-7000-8000-000000000001",
    "status": "STATUS_OK",
    "error_message": "",
    "server_ingested_ms": 1715626800123
  }]
}
```

### 6.2 PullEvents — POST /sync/pull

Clients request events they have not yet seen. Used on reconnect, on first app launch (before subscribing), and for paginated backfill.

**Request:** `PullRequest`

**Response:** `PullResponse`

**Example — pull all message and conversation events since HLC cursor:**

```json
POST /sync/pull HTTP/1.1
Content-Type: application/json

{
  "since": { "wall_ms": 1715000000000, "lamport": 0, "device_id": "000...000" },
  "entity_types": ["message", "conversation"],
  "limit": 500,
  "cursor": ""
}
```

If `has_more` is true in the response, pass the returned `cursor` in the next request. Continue until `has_more` is false.

### 6.3 Subscribe — WebSocket /sync/subscribe

After initial pull catchup, clients open a WebSocket subscription. The server pushes events in real time as other devices write them.

**Upgrade request:**
```
GET /sync/subscribe HTTP/1.1
Upgrade: websocket
Connection: Upgrade
Authorization: Bearer <nhost-jwt>
X-NClaw-Sync-Version: 1
X-NClaw-Device-Id: <device-uuid>
```

After the WebSocket handshake, the client sends a `SubscribeRequest` as the first message. The server begins streaming events with HLC greater than `since`. Events are serialized as `Event` proto3 messages.

The server does not buffer events between connections. If a client disconnects and reconnects, it should pull all events since its last known cursor before re-subscribing, to avoid gaps.

**Connection lifecycle:**
1. Client upgrades to WebSocket.
2. Client sends `SubscribeRequest`.
3. Server streams `Event` messages as they arrive.
4. Client sends `HeartbeatRequest` every 30 seconds.
5. Server responds with `HeartbeatResponse` within 5 seconds. If no heartbeat response in 10 seconds, the client reconnects.
6. If the server sends no event for 30 seconds, the client sends a heartbeat to verify the connection is alive.
7. Either side may close the connection. Clients reconnect immediately, backing off after 3 consecutive failures (see §11).

### 6.4 Heartbeat — WebSocket Ping

Every 30 seconds, the client sends a `HeartbeatRequest`. The server responds immediately with `HeartbeatResponse`. This serves two purposes: confirming the connection is alive (some proxies close idle WebSockets), and giving the client the server's current wall time for clock drift detection.

If the server's `wall_ms` in the response differs from the client's by more than 10 seconds, the client logs a warning but does not disconnect. If the skew exceeds 30 seconds, the client shows a UI warning that its system clock may be incorrect.

### 6.5 Snapshot — POST /sync/snapshot

New devices need to bootstrap their local state without pulling every event ever written (which could be millions). The snapshot endpoint returns the minimal set of events representing current state — one event per entity, carrying the entity's latest field values.

**Request:** `SnapshotRequest`

**Response:** `SnapshotResponse` (paginated; use `cursor` and `has_more` the same way as pull)

**When to use snapshot vs pull:**

- New device with no local state: snapshot.
- Device that was offline for less than 90 days: pull since last cursor.
- Device that was offline for more than 90 days: snapshot (event log may have been partially vacuumed).

The snapshot response also returns `snapshot_at_ms` — the server wall time when the snapshot was computed. After completing the snapshot, the client should immediately pull events since `snapshot_at_ms` to catch writes that happened during the snapshot computation.

---

## 7. Authentication Binding

Every device has a permanent identity, not just a user session. This matters because events carry `device_id` in their signature. A compromised session token cannot forge events from a different device.

### 7.1 Device Keypair Generation

On first run, the client generates an Ed25519 keypair:

```
private_key  [32]byte   -- stored in platform keychain; never leaves the device
public_key   [32]byte   -- shared with the server during device registration
device_id    UUID v7    -- generated at first run; stable for the device's lifetime
```

The private key is stored in the platform's secure enclave:

- **iOS/macOS:** Keychain Services with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Android:** Android Keystore System
- **Desktop (Tauri):** OS keyring via the `keyring` crate
- **Web:** IndexedDB with `SubtleCrypto` — key is non-exportable

Losing the device private key means losing the ability to create new events from that device. Existing events on the server remain readable and valid (signed with the old key, which is still on record).

### 7.2 Device Registration

Before pushing any events, the device registers its public key:

```
POST /devices HTTP/1.1
Authorization: Bearer <nhost-jwt>
Content-Type: application/json

{
  "device_id": "018e9c3f-0000-7000-8000-0000000000ab",
  "public_key": "base64url-encoded-ed25519-pubkey",
  "display_name": "Ali's iPhone 15 Pro",
  "platform": "ios",
  "client_version": "1.1.1"
}
```

Response:
```json
{
  "device_id": "018e9c3f-0000-7000-8000-0000000000ab",
  "registered_at": "2024-05-13T19:00:00Z",
  "status": "active"
}
```

The server stores the `(user_id, device_id, public_key)` tuple in `np_sync_devices`. A user can view and revoke their registered devices via the ɳClaw settings UI.

### 7.3 Event Signing

Before pushing an event, the client signs it. The signed message is the canonical JSON serialization of all event fields except `signature`, with keys sorted lexicographically:

```
message = canonical_json({
  "device_id": "...",
  "entity_id": "...",
  "entity_type": "...",
  "event_id": "...",
  "op": "insert",
  "payload": {...},
  "schema_version": 1,
  "tenant_id": null,
  "timestamp": {"device_id": "...", "lamport": 17, "wall_ms": 1715626800000},
  "user_id": "..."
})
signature = ed25519_sign(private_key, sha256(message))
```

The server verifies the signature using the registered public key. If verification fails, the event is rejected with `STATUS_ERROR` and message `INVALID_SIGNATURE`.

### 7.4 JWT + Device Binding

The nHost JWT carries the user's claims. The server additionally requires that `event.device_id` matches the `X-NClaw-Device-Id` header, which in turn must be a device registered under the JWT's `user_id`. If any of these three do not match, the push returns 401.

This three-way bind (JWT user, header device ID, event device ID) prevents one user from pushing events claiming to be from another user's device.

---

## 8. Versioning Policy

### 8.1 v1 is Frozen

Once this spec ships, the v1 contract is immutable. No field in §2.2 may be renamed, removed, or have its type changed. No enum value may be removed. The `schema_version: 1` wire encoding is stable forever.

Stability matters because old clients that have not updated must still be able to communicate with the current server. The server maintains v1 support indefinitely — or until a deprecation notice is published with at least 12 months of continued support.

### 8.2 v2 Must Be Additive

If v2 is ever introduced:

- All v1 fields remain present and semantically identical.
- New fields are added as optional (proto3 default: zero value if absent).
- New enum values may be added; existing enum values may not change.
- The `schema_version` field in the event distinguishes which version of the payload schema the client used.

The server runs v1 and v2 endpoints side-by-side at `/sync/v1/push`, `/sync/v1/pull`, etc. (v1 endpoints may omit the version prefix for backward compatibility). Clients negotiate which version to use via `X-NClaw-Sync-Version`.

### 8.3 Required Header

All requests must carry:

```
X-NClaw-Sync-Version: 1
```

If the header is absent, the server defaults to `1` for backward compatibility. If the header carries a version the server does not support, the server returns 400 with body:

```json
{
  "error": "UNSUPPORTED_VERSION",
  "supported_versions": [1],
  "requested_version": 3
}
```

### 8.4 Schema Mismatch in Events

If a client sends an event with `schema_version: 2` and the server only understands `schema_version: 1`, the event is rejected with `STATUS_SCHEMA_ERROR`. The server includes in the error detail the supported schema versions and a URL to the upgrade guide.

---

## 9. Bandwidth and Compression

### 9.1 Protocol Buffers Efficiency

Proto3 binary encoding is already compact. A typical `insert` event for a short message (200-byte content) encodes to roughly 350-400 bytes on the wire, compared to 600-700 bytes for the equivalent JSON. For large batches, this reduces push/pull payload by ~40%.

### 9.2 HTTP Gzip Compression

The server accepts and returns gzip-compressed bodies at the HTTP layer. Clients that support gzip send:

```
Accept-Encoding: gzip
Content-Encoding: gzip
```

The server always gzip-compresses responses larger than 1 KB. Gzip is effective even on binary proto payloads because event envelopes contain repeated strings (entity_type, op values, UUID bytes) that compress well.

### 9.3 Zstd for Batch Payloads

For push or pull batches with total body size ≥ 1 KB, clients may use zstd instead of gzip:

```
Accept-Encoding: zstd
Content-Encoding: zstd
```

Zstd achieves 10-20% better compression ratios than gzip at similar CPU cost. Use zstd for large offline catchup batches. Use gzip for small incremental pushes (simpler, universally supported).

### 9.4 Delta Payloads for Updates

Update events carry only changed fields in `payload`, not the full entity snapshot. A conversation title change sends:

```json
{ "payload": { "title": "New title" } }
```

Not:
```json
{ "payload": { "title": "New title", "persona_id": null, "parent_topic_id": "uuid", "archived": false, "pinned": true } }
```

This is particularly impactful for memory facts, which carry large embedding vectors — a metadata update to a fact does not re-send the vector.

### 9.5 Subscription Batching

The server does not push events one at a time over WebSocket. It buffers events for up to 50 ms and sends them as a batch. This coalesces rapid writes (e.g., the AI streaming a response token by token) into a smaller number of WebSocket frames. Clients handle the batch by processing each event in order.

---

## 10. Worked Examples

### 10.1 Single-Device Write

Alice is on her iPhone. She types a message. The app writes it to the local SQLite cache immediately and shows it in the UI without waiting for the server.

**Step 1 — Local write:**

```
client_db.insert("messages", {
  id: "018f2a1b-0000-7000-8000-000000000042",
  conversation_id: "018f2a1b-0000-7000-8000-000000000011",
  role: "user",
  content: "What did I decide about the proposal?",
  sync_status: "pending"
})
```

**Step 2 — Event creation:**

The sync engine creates an event envelope:

```json
{
  "event_id": "0193b6c0-7e7f-7000-8000-000000000001",
  "entity_type": "message",
  "entity_id": "018f2a1b-0000-7000-8000-000000000042",
  "op": "insert",
  "timestamp": { "wall_ms": 1715626800000, "lamport": 17, "device_id": "phone-uuid" },
  "user_id": "user-uuid",
  "device_id": "phone-uuid",
  "tenant_id": null,
  "payload": { "conversation_id": "...", "role": "user", "content": "What did I decide about the proposal?", "topic_ids": [], "created_at": "2024-05-13T19:00:00Z" },
  "schema_version": 1,
  "signature": "MEU..."
}
```

**Step 3 — Push to server:**

The sync engine pushes the event to `POST /sync/push`. The server validates the signature, checks device registration, applies LWW resolution (no prior event for this entity_id, so `insert` wins trivially), and writes to `np_sync_event_log`.

**Step 4 — Server ack:**

```json
{ "acks": [{ "event_id": "0193b6c0-...", "status": "STATUS_OK", "server_ingested_ms": 1715626800050 }] }
```

The client marks the local row `sync_status: "synced"`.

**Step 5 — Broadcast to other devices:**

The server's write to `np_sync_event_log` triggers a Hasura event subscription. Alice's MacBook, which is connected via WebSocket, receives the event within milliseconds. It processes the event, sees the entity is new, and inserts the message into its local cache. The message appears in the conversation on the MacBook.

### 10.2 Multi-Device Conflict

Alice is on a train with spotty WiFi. Her phone and her MacBook are both offline.

**Offline — phone:** Alice edits a conversation's title to "Proposal Notes". Her phone generates event E1:

```json
{
  "event_id": "E1",
  "entity_type": "conversation",
  "entity_id": "convo-42",
  "op": "update",
  "timestamp": { "wall_ms": 1715630000000, "lamport": 8, "device_id": "phone-uuid" },
  "payload": { "title": "Proposal Notes" }
}
```

**Offline — MacBook:** Simultaneously, Alice's MacBook (which synced a minute earlier) auto-renames the same conversation to "Q2 Proposal" based on the mux topic classification. Event E2:

```json
{
  "event_id": "E2",
  "entity_type": "conversation",
  "entity_id": "convo-42",
  "op": "update",
  "timestamp": { "wall_ms": 1715630002000, "lamport": 3, "device_id": "mac-uuid" },
  "payload": { "title": "Q2 Proposal" }
}
```

**Phone reconnects first.** Pushes E1. Server applies it. Title is now "Proposal Notes".

**MacBook reconnects.** Pulls events since its last cursor. Receives E1. Its local HLC advances. Then pushes E2.

**Server receives E2.** Compares E2 to the current head for `(conversation, convo-42)`:

- E1: `{ wall_ms: 1715630000000, lamport: 8, device_id: "phone-uuid" }`
- E2: `{ wall_ms: 1715630002000, lamport: 3, device_id: "mac-uuid" }`

Comparison per §3.3: E2.wall_ms (1715630002000) > E1.wall_ms (1715630000000). E2 is later. E2 wins.

**Resolution:** Title becomes "Q2 Proposal". Both devices converge. Phone receives E2 via its next pull (or push notification) and updates its local cache accordingly.

**Note on the outcome:** LWW means the later event wins regardless of intent. Alice's manual rename ("Proposal Notes") loses to the auto-rename ("Q2 Proposal") because the MacBook's wall clock was 2 seconds ahead. This is expected behavior. If Alice wants her manual rename to win, she edits the title again — that creates a new event with a later HLC, which wins.

### 10.3 Offline Catchup — Seven-Day Gap

Alice goes camping for a week. Her phone is offline. Her MacBook continues to sync. She sends 150 messages on the MacBook. The MacBook generates 150 events, all pushed to the server.

**Alice returns. Phone reconnects.**

**Step 1 — Phone checks last cursor.** It stored the HLC of the last event it received: `{ wall_ms: 1715000000000, lamport: 5, device_id: "mac-uuid" }`.

**Step 2 — Pull request:**

```json
POST /sync/pull
{
  "since": { "wall_ms": 1715000000000, "lamport": 5, "device_id": "mac-uuid" },
  "entity_types": [],
  "limit": 500,
  "cursor": ""
}
```

**Step 3 — Server response:**

The server queries `np_sync_event_log` for all events with HLC > since, ordered by HLC ascending. With 150 events, the response fits in one page (limit 500):

```json
{
  "events": [ /* 150 events */ ],
  "has_more": false,
  "cursor": ""
}
```

**Step 4 — Phone processes events.** For each event, the sync engine checks local state, applies LWW resolution, and upserts into the local SQLite cache. The phone's HLC advances to the maximum HLC seen in the response.

**Step 5 — Phone subscribes.** The phone opens a WebSocket subscription with `since` set to the HLC of the last pulled event. It is now caught up and receives real-time events.

**Total data transferred:** 150 events × ~400 bytes average = ~60 KB. Gzip-compressed to ~25 KB. Catchup completes in under a second on a 4G connection.

---

## 11. Error Handling

### 11.1 HTTP Endpoint Error Contracts

All HTTP endpoints use standard status codes plus a structured error body:

```json
{
  "error": "ERROR_CODE",
  "message": "Human-readable description",
  "detail": { /* optional extra context */ }
}
```

| HTTP Status | When |
|---|---|
| 200 | Success (even if some events had per-event errors — see PushResponse.acks) |
| 400 | Malformed request (invalid protobuf, missing required headers, unsupported schema version) |
| 401 | Authentication failure (invalid JWT, device ID mismatch, invalid signature) |
| 413 | Payload too large (batch >500 events or total body >4 MB) |
| 429 | Rate limited |
| 503 | Server temporarily unavailable |

### 11.2 Per-Event Errors in PushResponse

A 200 response on a push does not mean all events succeeded. Clients must inspect each `EventAck.status`:

- `STATUS_OK`: event ingested.
- `STATUS_DUPLICATE`: already seen. Safe to ignore.
- `STATUS_ERROR`: transient or permanent failure. See `error_message`.
- `STATUS_SCHEMA_ERROR`: client must upgrade.
- `STATUS_CLOCK_SKEW`: client clock too far ahead. Sync system clock.

### 11.3 Retry Semantics

Push requests are idempotent (event_id deduplication). Clients can and should retry any failed push.

Pull requests are safe to retry at any cursor position.

Retry schedule (exponential backoff with jitter):

```
attempt 1: immediate
attempt 2: 1s ± 0.5s jitter
attempt 3: 2s ± 1s jitter
attempt 4: 4s ± 2s jitter
attempt 5: 8s ± 4s jitter
attempt 6: 16s ± 8s jitter
...
max_interval: 60s
max_attempts: indefinite (online sync is a background operation)
```

The client stops retrying push for a specific event only if the server returns `STATUS_SCHEMA_ERROR` (client must upgrade first) or `STATUS_ERROR` with code `INVALID_SIGNATURE` (device key issue; requires user action).

All other errors — including 5xx, timeouts, and connection failures — are retried indefinitely.

### 11.4 WebSocket Reconnect

If the WebSocket closes for any reason:

1. Wait for backoff interval (same schedule as HTTP retry).
2. Pull events since last known cursor (to cover the gap while disconnected).
3. Re-open the WebSocket subscription with the updated `since` cursor.

Do not skip the pull step on reconnect. The pull-before-subscribe pattern ensures the client never has a gap in its event log.

---

## 12. Failure Modes

### 12.1 Network Partition

The client queues outbound events in the local SQLite database with `sync_status: "pending"`. When connectivity returns, the queue drains in order (oldest events first). The server's idempotency guarantee means it is safe to re-send events that may have reached the server before the partition.

While partitioned, the client continues operating normally. All reads come from local cache. All writes go to local cache and are queued for sync. The UI shows a "syncing" indicator but does not block.

### 12.2 Clock Skew

If a device's wall clock is significantly wrong (common after sleep/wake on systems with poor NTP), its events carry a skewed `wall_ms`. The server rejects events with `wall_ms` more than 30 seconds in the future (`STATUS_CLOCK_SKEW`). The client logs the error and surfaces a UI warning to check the system clock. Events are not discarded — they remain in the pending queue and are retried after the client corrects its clock.

Past-skewed clocks (where the device thinks it is in the past) are accepted but result in LWW losses when other devices have events with later timestamps.

### 12.3 Duplicate Events

The `event_id` (UUID v7) is globally unique per event. The server maintains a unique index on `np_sync_event_log.event_id`. If the same event arrives twice (common after retries), the second arrival returns `STATUS_DUPLICATE` and is a no-op. No double-processing, no duplicate rows.

### 12.4 Oversized Events

If a payload exceeds 64 KB, the client must chunk the event before pushing (§2.3). If a client pushes an event with payload > 64 KB without chunking, the server rejects it with HTTP 413 and error code `PAYLOAD_TOO_LARGE`. The client then applies the chunking algorithm and retries.

Memory fact events with large embedding vectors are the most likely source of oversized payloads. The sync engine checks payload size before creating the event envelope.

### 12.5 Schema Mismatch

If a client on an old version pushes events with `schema_version: 1` and the server has migrated to a new schema, the server processes the event using the v1 schema rules. The server never rejects a v1 event because a v2 schema exists — backward compatibility is a hard requirement.

If a client on a new version pushes events with `schema_version: 2` and the server only knows v1, the event is rejected with `STATUS_SCHEMA_ERROR`. The error response includes `detail.upgrade_url` pointing to the server upgrade guide. In this case, the user needs to update their nSelf backend via `nself update`.

### 12.6 Hasura Subscription Failure

If the Hasura subscription WebSocket drops, events pushed by other devices during the gap will not arrive via push. The client's reconnect logic (§11.4) — pull since last cursor, then re-subscribe — covers this gap. No events are lost; they are all in the server event log waiting to be pulled.

If Hasura becomes unavailable entirely, the client falls back to polling: `POST /sync/pull` every 30 seconds with the last known cursor. The polling fallback activates automatically when the WebSocket cannot be established after 3 attempts. It deactivates and returns to WebSocket subscription when connectivity is restored.

### 12.7 Server Event Log Corruption

The `np_sync_event_log` table is the source of truth. Its durability is backed by PostgreSQL on the nSelf backend, which uses WAL (Write-Ahead Logging) and should be backed up regularly. If the event log is corrupted or lost:

1. The server returns errors on all pull and push requests.
2. Clients queue pushes locally and retry.
3. Clients with complete local event logs can be used to reconstruct the server event log by pushing their entire local event history. The deduplication mechanism handles overlapping events correctly.

This is not automatic recovery — it requires operator action. The nSelf backend documentation describes the recovery procedure in the disaster recovery runbook.

---

## Appendix A: np_sync Database Schema (Reference)

The following SQL schema is informational. The authoritative schema lives in the plugins-pro/nself-sync migration files.

```sql
-- Event log: immutable, append-only
CREATE TABLE np_sync_event_log (
  event_id        UUID PRIMARY KEY,
  entity_type     TEXT NOT NULL,
  entity_id       UUID NOT NULL,
  op              TEXT NOT NULL CHECK (op IN ('insert', 'update', 'delete')),
  hlc_wall_ms     BIGINT NOT NULL,
  hlc_lamport     INTEGER NOT NULL,
  hlc_device_id   UUID NOT NULL,
  user_id         UUID NOT NULL REFERENCES np_users(id),
  device_id       UUID NOT NULL,
  tenant_id       UUID,
  payload         JSONB,
  schema_version  INTEGER NOT NULL DEFAULT 1,
  signature       TEXT NOT NULL,
  server_received_ms BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW()) * 1000
);

CREATE INDEX np_sync_event_log_hlc ON np_sync_event_log (hlc_wall_ms, hlc_lamport, hlc_device_id);
CREATE INDEX np_sync_event_log_entity ON np_sync_event_log (entity_type, entity_id);

-- Registered devices
CREATE TABLE np_sync_devices (
  device_id    UUID PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES np_users(id),
  public_key   TEXT NOT NULL,
  display_name TEXT,
  platform     TEXT,
  client_version TEXT,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at   TIMESTAMPTZ
);

-- Per-field LWW tracking
CREATE TABLE np_sync_field_heads (
  entity_type  TEXT NOT NULL,
  entity_id    UUID NOT NULL,
  field_name   TEXT NOT NULL,
  hlc_wall_ms  BIGINT NOT NULL,
  hlc_lamport  INTEGER NOT NULL,
  hlc_device   UUID NOT NULL,
  value_json   JSONB,
  PRIMARY KEY (entity_type, entity_id, field_name)
);

-- Tombstones
CREATE TABLE np_sync_tombstones (
  entity_type  TEXT NOT NULL,
  entity_id    UUID NOT NULL,
  hlc_wall_ms  BIGINT NOT NULL,
  hlc_lamport  INTEGER NOT NULL,
  hlc_device   UUID NOT NULL,
  deleted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (entity_type, entity_id)
);
```

---

## Appendix B: Client Implementation Checklist

Implementors building a new client should verify:

- [ ] Device keypair generated and stored in platform secure enclave on first run
- [ ] Device registered with server before first push
- [ ] HLC state maintained persistently (survives app restart)
- [ ] All events signed with device private key
- [ ] Events queued locally with `sync_status: pending`; push on connectivity
- [ ] Push retry with exponential backoff + jitter
- [ ] Idempotent push (same event may be sent multiple times safely)
- [ ] Pull on app foreground if WebSocket was closed while backgrounded
- [ ] Pull-then-subscribe pattern on reconnect (never subscribe without pulling the gap first)
- [ ] Heartbeat every 30 seconds on open WebSocket
- [ ] Chunk oversized payloads (>64 KB) before pushing
- [ ] Handle `STATUS_DUPLICATE` as success (idempotency)
- [ ] Handle `STATUS_SCHEMA_ERROR` by prompting server upgrade
- [ ] Handle `STATUS_CLOCK_SKEW` by surfacing a UI warning about system clock
- [ ] Snapshot on first-device bootstrap (not pull)
- [ ] Tombstone handling: delete wins over older insert/update; newer insert wins over delete

---

*This document is generated as part of P101 S17. For questions, file a PCI to the nself inbox.*
