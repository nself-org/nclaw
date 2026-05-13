# ADR-0010: Sync Direction (Local-First with Eventual Consistency)

**Status:** Accepted 2026-05-11  
**Context:** Multi-device writes must feel instant locally but eventually propagate to other devices.  
**Decision:** Local-first: writes land locally first, queue to server, server fans out via subscriptions.  

## Context

Latency matters for UX. Writing to the server synchronously (wait for 200ms round-trip) feels slow. But writes must eventually reach other devices and the server must be the record of truth.

## Decision

Write flow:
1. User writes locally → lands in local database immediately (instant UX).
2. Sync layer queues write to server asynchronously.
3. Server processes write, stores in its database, fans out to other devices via Hasura subscriptions.
4. Other devices receive subscription notification, apply write to their local database.

The server is the record of truth. Conflicts (rare for personal data) are resolved using LWW per entity. An optional manual-resolve UI is available for cases where the user wants to recover the earlier edit.

## Rationale

- **Instant local feedback:** Users feel responsiveness immediately; no waiting for round-trip.
- **Server is source of truth:** If device crashes, the server has the definitive version.
- **Eventual consistency:** Other devices get updates in seconds, not milliseconds (acceptable tradeoff).

## Consequences

**Positive:**
- Excellent offline-first UX; app feels instant even on slow networks.

**Negative:**
- Brief window where devices are out of sync (100–500ms typically). User may see stale data briefly.
- Conflict resolution UI is complex (rare, but needed for advanced users).

## Alternatives Considered

- **Server-first:** Synchronous writes to server. Simpler, but user waits for round-trip every keystroke.
- **Full CRDT:** No server needed, but complex and overkill for single-user.

## References

- Local-first software: https://localfirst.fm/  
- Eventual consistency: https://www.allthingsdistributed.com/2008/12/eventually_consistent.html
