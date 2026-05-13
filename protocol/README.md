# nclaw/protocol/

Protocol specifications for nClaw cross-platform state replication. This directory is consumed by server implementors (plugins-pro/nself-sync) and client implementors (desktop/, mobile/, core/).

## Documents

| File | What it covers | Status |
|---|---|---|
| [sync-protocol.md](sync-protocol.md) | Event envelope, HLC clock, LWW conflict resolution, wire format, authentication binding, worked examples | v1 — canonical |
| vault-protocol.md | E2E key exchange, device pairing, keypair rotation | Planned |
| plugin-mcp-protocol.md | MCP-style plugin call protocol — how local clients invoke server-side plugin tools | Planned |

## Versioning

The sync protocol follows a strict compatibility contract: v1 fields are frozen (never renamed or removed). New fields in a future v2 are always optional and additive. Clients negotiate the version via the `X-NClaw-Sync-Version` HTTP header. The server runs all supported versions side by side.

See [sync-protocol.md §8](sync-protocol.md#8-versioning-policy) for the full policy.

## Architecture Decisions Cross-Referenced

- **Decision #5** — event-log model + LWW conflict resolution + Hasura subscriptions for push
- **Decision #7** — conversation auto-topics via plugin-mux (topic events are sync'd entities)
- **Decision #10** — server-of-record: clients are caches; the server event log is authoritative

All three decisions were locked during P101 STORM planning. They inform every design choice in sync-protocol.md.

## Quick Links

- [Event Envelope schema](sync-protocol.md#2-event-envelope)
- [Hybrid Logical Clock algorithm](sync-protocol.md#3-hybrid-logical-clock)
- [Conflict resolution rules](sync-protocol.md#4-lww-conflict-resolution)
- [Protobuf schema](sync-protocol.md#51-primary-format-protocol-buffers)
- [Worked examples](sync-protocol.md#10-worked-examples)
- [Error contracts](sync-protocol.md#11-error-handling)
