# Memory

**Status:** Active

## Overview

Memory is the core differentiator of ɳClaw. Every conversation is captured into a Postgres-backed knowledge graph. Topics are auto-detected. Facts, decisions, and entities are extracted on every turn. Subsequent conversations retrieve relevant context automatically — no manual prompt engineering, no "New Chat" model.

The sidebar groups conversations by topic, not by date or "thread name". Topics branch when the conversation diverges. Memory compounds: facts mentioned across separate conversations link automatically. The user's life ends up organized in Postgres, not lost in a chat scrollback.

The implementation lives in the `claw` and `mux` pro plugins on the user's nSelf backend. PostgreSQL with `pgvector` (semantic search) and `ltree` (topic hierarchies) provides the storage. Redis caches recent context. MeiliSearch handles full-text search. The Flutter client renders the topic tree, search, and memory inspector.

## Requirements

| Item | Required | Notes |
|------|----------|-------|
| ɳSelf CLI | 1.0+ | F01-MASTER-VERSIONS |
| Plugin: `claw` | Yes | Pro tier — owns memory tables |
| Plugin: `mux` | Yes | Pro tier — topic detection, fact extraction |
| Plugin: `ai` | Yes | Pro tier — embeddings + classification |
| Service: PostgreSQL with `pgvector` + `ltree` | Yes | F08-SERVICE-INVENTORY |
| Service: Redis | Yes | F08 |
| Service: MeiliSearch | Optional | F08 — full-text search |
| Tier | Pro ($1.99/mo) | per F07-PRICING-TIERS |
| Bundle | ɳClaw Bundle ($0.99/mo) | per F06-BUNDLE-INVENTORY |

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `CLAW_MEMORY_ENABLED` | `true` | Master switch — memory capture on/off |
| `CLAW_MEMORY_TOPIC_DETECTION` | `true` | Auto-detect and group by topic |
| `CLAW_MEMORY_EMBEDDING_PROVIDER` | (per ai plugin) | Embedding model for pgvector |
| `CLAW_MEMORY_RETENTION_DAYS` | `0` (forever) | Auto-purge memory after N days; 0 = never |

## Usage

### Talking to ɳClaw

Memory works automatically. Just talk. No commands needed. Topics, facts, and entities are captured on every turn. The sidebar updates in near-real-time via Hasura GraphQL subscriptions.

### Searching memory

Use the sidebar search box. Queries match by:

- Semantic similarity (pgvector embeddings)
- Topic name (ltree path matching)
- Full text (MeiliSearch, if installed)

Or query directly via the `claw` plugin REST endpoint:

```bash
curl "https://your-backend/v1/plugins/claw/memory/search?q=last+week+meetings" \
  -H "Authorization: Bearer $JWT"
```

### Inspecting and editing memory

The Memories screen shows extracted facts, decisions, and entities. Each entry can be:

- Edited (correct a wrong fact)
- Deleted (remove a sensitive entry)
- Pinned (always include in context)

### Branching topics

When the conversation shifts (e.g., from "iOS build" to "Android push setup"), `mux` detects the topic change and creates a child topic in the ltree. The sidebar shows the parent topic with the child as a sub-thread, with breadcrumb navigation back.

### Cross-conversation linking

Mention an entity ("Project X") in conversation A. Mention it again in conversation B. Both conversations link to the same entity record. Searching for "Project X" surfaces both.

## Limitations

- Cross-account memory sharing is not yet supported. Memory is per-account, per-device.
- Cross-device sync requires QR pairing or a short-code transfer. No implicit cloud sync.
- The embedding model must be configured before first use. Switching models mid-stream requires rebuilding the index (manual flow).
- Large memory growth eventually requires PostgreSQL tuning (vacuum, index maintenance) — standard Postgres ops.
- E2E-encrypted memory cannot be searched server-side semantically (the server only sees ciphertext). On-device search only.

### Known issues

None currently tracked.

## Troubleshooting

### Sidebar topics don't update

**Symptom:** Conversations happen but the sidebar topic tree doesn't change.
**Cause:** `CLAW_MEMORY_ENABLED=false`, `CLAW_MEMORY_TOPIC_DETECTION=false`, or `mux` plugin missing.
**Fix:** Set both env vars to `true`. `nself plugin install mux`. Run `nself build && nself restart claw mux`.

### Search returns empty

**Symptom:** Sidebar search returns no results despite conversations.
**Cause:** Embeddings have not been generated (embedding provider not configured), or `pgvector` extension not enabled in Postgres.
**Fix:** Verify `CLAW_MEMORY_EMBEDDING_PROVIDER` is set. Check `pgvector` is enabled: `psql -c "SELECT * FROM pg_extension WHERE extname='vector';"`.

### Memory entry is wrong

**Symptom:** A fact captured by the AI is incorrect.
**Cause:** AI extraction is imperfect; user can edit.
**Fix:** Open the Memories screen, edit or delete the entry. The corrected entry will be used in subsequent context retrieval.

### Topics multiply too aggressively

**Symptom:** Every short message creates a new topic.
**Cause:** Topic detection threshold is too sensitive in the `mux` plugin config.
**Fix:** Tune the `mux` topic detection threshold (per `mux` plugin docs). Restart `mux` after config change.

## Related

- [[AI-Chat]] — chat surface that drives memory capture
- [[Personas]] — persona-scoped memory
- [[E2E-Encryption]] — encrypted memory storage
- [[Architecture-Deep-Dive]] — memory data model and flow
- [[Features]] — full feature index

← [[Features]] | [[Home]] →
