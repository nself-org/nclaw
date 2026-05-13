# ADR-0005: Sync Engine (Event Log + LWW)

**Status:** Accepted 2026-05-11  
**Context:** Multi-device data sync must work offline, handle eventual consistency, and resolve conflicts.  
**Decision:** Custom event log with last-write-wins (LWW) conflict resolution and Hasura subscriptions.  

## Context

ɳClaw is single-user across multiple devices (desktop, phone, tablet). Writes must land locally (instant feedback), queue to the server, and replicate to other devices. Conflicts are rare for personal data but must be handled gracefully.

## Decision

Sync engine architecture:
- **Event log:** Each write is appended as an event with timestamp, entity ID, and payload.
- **Last-write-wins:** Per-entity conflict resolution using server timestamp (clock is authoritative).
- **Hasura subscriptions:** Server fans out writes to connected devices in real-time.
- **Offline queue:** Local writes persist until server confirms receipt.

This is **not** full CRDT (collaborative, causally ordered). It is optimized for single-user multi-device.

Upgrade path to CRDT is reserved for v1.3.x if multi-device write conflicts become real.

## Rationale

- **Event log** provides durable record of changes and enables audit trails.
- **LWW** is simple, deterministic, and works well for personal data (who cares if phone edit wins over laptop edit, as long as one of them wins?).
- **Hasura subscriptions** are real-time and leverage existing nSelf infrastructure.
- **Offline queue** ensures no writes are lost, even if network drops mid-sync.

## Consequences

**Positive:**
- Fast local writes; eventual consistency is acceptable for personal data.
- Simpler conflict logic than full CRDT.

**Negative:**
- LWW loses information (earlier write is discarded silently). Manual UI is needed for rare cases where user wants to recover it.
- Event log grows unbounded; compaction/archival strategy is needed for long-term use.

## Alternatives Considered

- **Full CRDT:** Better for collaborative work, but overkill for single-user and much slower.
- **Custom conflict resolution:** User chooses which edit wins. Annoying for personal data.

## References

- Event sourcing: https://martinfowler.com/eaaDev/EventSourcing.html  
- Last-write-wins: https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type#LWW-element-set  
- Hasura subscriptions: https://hasura.io/docs/latest/subscriptions/
