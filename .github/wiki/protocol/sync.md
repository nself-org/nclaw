# Sync Protocol Specification — nClaw v1.1.1

## Overview

ɳClaw's sync engine maintains client-server consistency through an append-only event log and last-write-wins conflict resolution. The server is the record of truth. Each device generates Ed25519-signed event entries; the server persists them with server-corrected timestamps. A third-party developer could build a compatible client from this specification alone.

The event log captures all state mutations—topic creation, message inserts, memory updates, conversation deletions—as discrete, auditable records. Clients replay missed events on reconnection to reconstruct their local state deterministically.

## Wire Format

Events are JSON objects transmitted over GraphQL and persisted in the `np_sync_events` table. Each event carries operational metadata and cryptographic proof of origin.

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "entity": "message",
  "entity_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "op": "create",
  "fields": {
    "topic_id": "uuid",
    "content": "...",
    "role": "user",
    "created_at": "2026-05-13T10:00:00Z"
  },
  "timestamp": "2026-05-13T10:00:00.123456Z",
  "device_id": "device-uuid",
  "signature": "base64-encoded-ed25519-signature"
}
```

Entity types: `message`, `topic`, `memory`, `conversation`. Operations: `create`, `update`, `delete`. The `fields` object contains the delta; client applies it atomically. Timestamps are ISO8601-formatted; server always overwrites `timestamp` with server time before storing.

## Transport

Events flow over two channels: **mutations** (client→server) and **subscriptions** (server→client).

**Mutations** are GraphQL mutations (`insertSyncEvent`, `updateSyncEvent`) sent to the Hasura API over HTTPS. Client signs the event, POSTs to `https://<backend>/graphql` with Authorization header carrying a JWT token.

**Subscriptions** are real-time subscriptions over WebSocket (WSS). Client connects to `wss://<backend>/sync/subscribe` **with no token in the URL** (URLs are logged at every proxy hop; a token in the URL leaks at every layer). Immediately after the WebSocket upgrade completes, the client sends a single text frame:

```json
{"type":"auth","token":"<JWT>"}
```

The server validates the frame within 5 seconds; failure to deliver a valid auth frame in that window causes the server to close the connection with code 4001. HTTP endpoints (`POST /sync/push`, `POST /sync/pull`, `POST /sync/snapshot`, `POST /sync/ack`) carry the JWT in the `Authorization: Bearer <JWT>` header — also never in the URL.

**JWT token** format (issued by `nself-auth` plugin):
```json
{
  "sub": "user-uuid",
  "tenant_id": "tenant-uuid (nullable for personal instances)",
  "device_id": "device-uuid",
  "iat": 1715594400,
  "exp": 1715680800
}
```

Token validity: 24 hours. Refresh via `/auth/refresh` before expiry.

## Conflict Resolution

When two devices mutate the same field, last-write-wins (LWW) applies on a per-field basis using the `timestamp` value. The server ensures clock skew does not break causality by fetching the server time from its Trusted Time API (NTP or leap-second-aware system clock) at the moment of insertion. If two events have identical `timestamp`, tie-break lexicographically on `(device_id, event_id)`.

Hard deletes (op = "delete") are tombstones; they survive for 90 days in the event log before being purged. A read query filters them out; the tombstone itself documents the deletion intent for audit purposes.

## Event Log Table Schema

```sql
CREATE TABLE np_sync_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  tenant_id UUID,
  entity TEXT NOT NULL,
  entity_id UUID NOT NULL,
  op TEXT NOT NULL CHECK (op IN ('create', 'update', 'delete')),
  fields JSONB NOT NULL,
  client_ts TIMESTAMPTZ NOT NULL,
  server_ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  device_id UUID NOT NULL,
  signature BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sync_events_user_ts ON np_sync_events(user_id, server_ts);
CREATE INDEX idx_sync_events_entity ON np_sync_events(entity, entity_id);
```

Hasura applies a row filter: `{"_or":[{"user_id":{"_eq":"X-Hasura-User-Id"}},{"tenant_id":{"_eq":"X-Hasura-Tenant-Id"}}]}`. Only the authenticated user or their tenant can read/insert events.

## Client State

Clients maintain a local SQLite or PGLite cursor: `last_seen_server_ts`. On startup or reconnection, the client fetches all events where `server_ts > last_seen_server_ts` ordered ascending by `server_ts`, replays them in order against the local database, then advances the cursor. This deterministic replay reconstructs the exact state the server holds.

```sql
-- Local client DB
CREATE TABLE _sync_cursor (
  user_id TEXT PRIMARY KEY,
  last_seen_server_ts TEXT NOT NULL
);
```

Clients MUST replay events in server-timestamp order, not by ID or arrival time, to maintain causal consistency.

## Bootstrapping a New Device

When a new device runs ɳClaw for the first time:

1. Generate a new Ed25519 keypair (`pk`, `sk`).
2. POST the public key + device label to `/devices` (authenticated):
   ```json
   {"public_key": "base64", "label": "My iPhone"}
   ```
   Server returns `device_id`.
3. Fetch the full snapshot via `/sync/snapshot?since=0` to hydrate the local database.
4. Set `last_seen_server_ts` to the snapshot's max `server_ts`.
5. Subscribe to `np_sync_events` subscription (WSS) and process incoming events live.

All future mutations are signed with `sk` and include `device_id` in the payload.

## Trust Model

The server cannot decrypt user data stored in the encrypted vault; those payloads are opaque blobs. However, sync event metadata (entity type, operation, field names, timestamps) is readable by the server. This is intentional: the server must understand causality and conflict resolution.

Event signatures prove that a specific device authored an event. The server does NOT verify signatures before storing (for performance); clients verify signatures when replaying to detect tampering. A compromised device signing key can create false events, but only the server-accepted `server_ts` value determines conflicts—a compromised key cannot backdating events or alter the server's timestamp.

## Versioning

The current protocol is v1. All sync requests include the header `X-NClaw-Sync-Version: 1`. Breaking changes will increment the major version (v2 ships alongside v1 in a deprecation period). Clients request their target version; servers that do not support a version reject the request with HTTP 426 Upgrade Required.

## Failure Modes

**Network Partition.** Client queues mutations locally; on reconnection, it submits the queued events and fetches missed events from the server. Replaying both applied mutations and new remote events deterministically resolves conflicts.

**Clock Skew.** If a client's clock is ahead of the server, the server timestamp always wins. The client is re-informed of the actual event timestamp and updates its local cursor accordingly.

**Duplicate Events.** If a client resubmits an event (e.g., due to a crash during acknowledgment), the server deduplicates by `id` (primary key). Resubmission is idempotent.

**Oversized Event.** Events larger than 64 KB are split into chunks client-side and reassembled server-side before persistence. Each chunk is signed independently with the same `event_id` root.

---

**Version:** 1.0  
**Last Updated:** 2026-05-13  
**Repo:** nself-org/nclaw  
**Related ADR:** [0005 — Sync Engine](../adr/0005-sync-engine) · [0010 — Sync Direction](../adr/0010-sync-direction)
