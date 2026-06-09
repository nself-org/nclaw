# nClaw Memory Ingestion and Sync Pipeline

**Feature ID:** F-NCLAW:memory-ingestion-sync  
**Status:** Planned (P1-E3-W6-S06-T04)  
**Depends on:** T01 (cb_* schema), T02 (hybrid retrieval), T03 (relationship graph extraction)  
**Blocks:** P1-E3-W7-S07-T01 (nself-ai-gateway integration), P1-E5-W10-S10-T01 (cloud sync server)

---

## Overview

The memory ingestion pipeline collects content from 5 source types (chat turns, file uploads, inbox messages, tasks, and agent outputs), deduplicates, chunks, embeds, and stores into the local semantic brain (`cb_*` tables). A WAL-style offline queue handles network interruptions. A sync state machine manages local-only → cloud sync lifecycle. PII is redacted before any embedding is generated.

---

## Source Adapters

Each adapter maps its source-native fields to the canonical `cb_*` column set. All adapters populate: `source_type` (enum), `source_id` (TEXT), `ingested_at` (TIMESTAMPTZ = NOW()), `local_only` (BOOLEAN DEFAULT true), `pii_redacted` (BOOLEAN DEFAULT false — updated by redaction pass before embedding).

### 1. Chat Turn

| Source field | cb_* column | Notes |
|---|---|---|
| `message_id` | `source_id` | Stable per turn |
| `role` | `metadata->>'role'` | `user` \| `assistant` \| `system` |
| `conversation_id` | `metadata->>'conversation_id'` | FK candidate for cb_conversations |
| `turn_index` | base for `chunk_seq` | chunk_seq = turn_index * 100 + chunk_offset |
| `content` | chunk pipeline input | Tokenized → chunked → embedded |
| `created_at` | `ingested_at` | |

**Source type:** `chat_turn`

**Error handling:** missing `message_id` or empty `content` → skip with WARNING log; never partial ingest.

### 2. File Upload

| Source field | cb_* column | Notes |
|---|---|---|
| `file_id` | `source_id` | Stable file identifier |
| `file_path` | `metadata->>'file_path'` | Relative path |
| `mime_type` | `metadata->>'mime_type'` | Determines tokenizer: `text/*` = standard; `application/pdf` = extract first |
| `file_hash` | `metadata->>'file_hash'` | SHA-256 of file content; used for re-ingest detection |
| `upload_at` | `ingested_at` | |

**Source type:** `file_upload`

**Error handling:** missing `file_id` or unreadable content → skip with WARNING; no partial chunk rows.

### 3. Inbox Message

| Source field | cb_* column | Notes |
|---|---|---|
| `message_id` | `source_id` | |
| `sender` | `metadata->>'sender'` | |
| `subject` | included in chunk pipeline | Prepended to body with `Subject: {subject}\n\n{body}` for context |
| `body` | chunk pipeline input | |
| `received_at` | `ingested_at` | |

**Source type:** `inbox_message`

**Error handling:** missing `message_id` → skip; empty body with subject → ingest subject-only as single chunk (min viable content).

### 4. Task

| Source field | cb_* column | Notes |
|---|---|---|
| `task_id` | `source_id` | |
| `title` | chunk pipeline input | `{title}\n\n{description}` concatenated |
| `description` | chunk pipeline input | May be empty; title alone is valid |
| `status` | `metadata->>'status'` | `todo` \| `in_progress` \| `done` \| `cancelled` |
| `project_id` | `metadata->>'project_id'` | FK candidate for cb_entities |
| `updated_at` | `ingested_at` | Re-ingest when task updated |

**Source type:** `task`

**Error handling:** missing `task_id` → skip; empty title AND description → skip with WARNING.

### 5. Agent Output

| Source field | cb_* column | Notes |
|---|---|---|
| `agent_run_id` | `source_id` | |
| `agent_type` | `metadata->>'agent_type'` | e.g. `code_review`, `qa`, `research` |
| `output_content` | chunk pipeline input | Full text output |
| `completed_at` | `ingested_at` | |

**Source type:** `agent_output`

**Error handling:** missing `agent_run_id` or empty `output_content` → skip with WARNING.

---

## Dedupe Strategy

**Dedupe key:** `SHA-256(source_type || '|' || source_id || '|' || chunk_seq::text || '|' || chunk_text)`

Stored in `cb_embeddings.dedupe_hash` (TEXT, indexed). Insert path:

1. Compute dedupe_hash for each candidate chunk.
2. Check `cb_embeddings` for existing `dedupe_hash`.
3. **Hash match (collision):** skip re-embedding; `UPDATE cb_embeddings SET ingested_at = NOW() WHERE dedupe_hash = $1`. No new row, no duplicate vector.
4. **No match:** insert new row, proceed to embedding.

**Out-of-order chunks:** accepted unconditionally by `chunk_seq` value. Chunks from a given `source_id` are sorted by `chunk_seq ASC` at retrieval time; no special ingestion-time ordering required.

---

## Chunking Strategy

**Config keys:**
- `NCLAW_CHUNK_MAX_TOKENS` — default `512`
- `NCLAW_CHUNK_OVERLAP_TOKENS` — default `64`

### Algorithm

1. Tokenize content to count tokens.
2. If `token_count <= NCLAW_CHUNK_MAX_TOKENS`: single chunk (chunk_seq = base).
3. If longer: split with overlap using boundary detection priority (below).
4. Final (tail) chunk may be shorter than max — never pad.

### Boundary Detection Priority

| Priority | Rule | When Used |
|---|---|---|
| 1 | Sentence boundary | Preferred — split at sentence end `.`, `!`, `?` followed by whitespace |
| 2 | Paragraph boundary | Double newline `\n\n` |
| 3 | Fixed-length fallback | When no sentence or paragraph boundary found within max-token window |

### Platform Tokenizer Split (LEDGER §G)

| Platform | Tokenizer | Sentence splitter |
|---|---|---|
| Desktop (`nclaw/desktop/`) | NLTK `sentence_tokenize` binding (when available); regex fallback | NLTK |
| Mobile (`nclaw/mobile/`) | Regex-only (no NLTK Python binding on device) | Regex |
| Locked fallback (both) | Regex sentence splitter: `r'(?<=[.!?])\s+'` | Regex |

The regex splitter is the canonical fallback on all platforms. Desktop may use NLTK for higher accuracy when available.

---

## Embedding Pipeline

### Model and Interface

- **Model:** BGE-M3 via TEI sidecar (ADR-005 nclaw preset: dense + lexical + reranker)
- **Gateway lane:** `embedding` lane of `nself-ai-gateway` (ADR-006)
- **Call interface:** `Provider.Embed(ctx, text string, expectedDim int) ([]float32, error)`
  - Underlying transport: HTTP POST `/embed` to TEI sidecar
  - `expectedDim` = 1024 (FLOAT4, ADR-005)
- **Batch size:** 32 chunks per request — config key `NCLAW_EMBED_BATCH_SIZE` (default 32)

### Retry Policy

```
retry_count  = 0
max_retries  = NCLAW_EMBED_MAX_RETRIES (default 3)
backoff_base = 1s
backoff_mult = 2x (exponential)

on error:
  if retry_count < max_retries:
    sleep(backoff_base * 2^retry_count)
    retry_count++
  else:
    INSERT into cb_ingestion_queue status=failed_embed
    return
```

### ONNX Local Fallback

If TEI sidecar is unavailable AND `NCLAW_EMBED_ONNX_PATH` is set:
- Use local ONNX runtime at path specified by `NCLAW_EMBED_ONNX_PATH`.
- Same `expectedDim = 1024` requirement; model must be BGE-M3 ONNX export.
- If both TEI and ONNX unavailable: queue all pending chunks in `cb_ingestion_queue` with `status=queued`; resume when either becomes available.

---

## PII Redaction

**Runs BEFORE embedding — the original unredacted text is never persisted in any `cb_*` table.**

### Pattern List

| Type | Pattern Reference | Replacement |
|---|---|---|
| Email | RFC 5321 regex: `[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}` | `[REDACTED:email]` |
| Phone | E.164 + common US: `(\+1)?[\s\-.]?\(?\d{3}\)?[\s\-.]?\d{3}[\s\-.]?\d{4}` | `[REDACTED:phone]` |
| SSN | `\d{3}-\d{2}-\d{4}` | `[REDACTED:ssn]` |
| Credit card | Luhn-valid 16-digit: `\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}` | `[REDACTED:credit_card]` |
| IBAN | IBAN prefix: `[A-Z]{2}\d{2}[A-Z0-9]{4}\d{7}([A-Z0-9]?){0,16}` | `[REDACTED:iban]` |

### Redaction Process

1. Apply all patterns to `chunk_text`.
2. If any match found: replace in-place with `[REDACTED:<type>]`; set `pii_redacted = true` on the `cb_embeddings` row.
3. Proceed to embedding with redacted text.
4. The original unredacted text is discarded and never persisted.

**Note:** `pii_redacted` flag on `cb_embeddings` indicates at least one pattern matched. The specific type is embedded in the `[REDACTED:<type>]` token — it can be inferred from the stored chunk_text.

---

## Sync State Machine

### States

```
local_only ──→ pending_sync ──→ synced
                                  │
                                  └──→ conflict
```

| State | Meaning |
|---|---|
| `local_only` | Chunk exists only on this device. Cloud sync is not enabled or not yet attempted. |
| `pending_sync` | User enabled cloud sync; chunk is queued for upload to cloud on next sync cycle. |
| `synced` | Cloud server has confirmed receipt. Server and local are in agreement. |
| `conflict` | Server version differs from local version detected on next sync pull. |

### Transitions

| From | To | Trigger |
|---|---|---|
| `local_only` | `pending_sync` | User enables cloud sync AND connectivity available |
| `pending_sync` | `synced` | Server confirms receipt (HTTP 200 or gRPC OK) |
| `synced` | `conflict` | Server version's `updated_at` differs from local on sync pull |
| `conflict` | `synced` | Conflict resolved (see below) |
| `pending_sync` | `local_only` | Connectivity lost before server confirms; retry at next reconnect |

### Conflict Resolution (P1)

**Algorithm:** last-write-wins by `updated_at`.
- Compare local `cb_sync_state.last_synced_at` vs server-returned `updated_at`.
- Whichever is newer wins.
- The losing version is preserved in `conflict_payload` JSONB for manual recovery.

**Future path (noted, not implemented in P1):** CRDT-based merge for commutative operations (e.g., fact accumulation). Implementation deferred to post-P1 roadmap.

### cb_sync_state Table Schema

```sql
CREATE TABLE cb_sync_state (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type    TEXT NOT NULL,                          -- 'embedding' | 'entity' | 'conversation'
  entity_id      UUID NOT NULL,                         -- FK to the tracked entity
  sync_state     TEXT NOT NULL DEFAULT 'local_only',    -- local_only | pending_sync | synced | conflict
  last_synced_at TIMESTAMPTZ,                           -- NULL until first sync
  conflict_payload JSONB,                               -- populated only on conflict state
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(entity_type, entity_id)
);
```

---

## Offline Queue

**Table:** `cb_ingestion_queue`

### Schema

```sql
CREATE TABLE cb_ingestion_queue (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type   TEXT NOT NULL,                          -- one of 5 source type enums
  source_id     TEXT NOT NULL,
  raw_content   JSONB NOT NULL,                         -- full source payload before processing
  queued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  retry_count   INT NOT NULL DEFAULT 0,                 -- max 5 attempts
  status        TEXT NOT NULL DEFAULT 'queued',         -- queued | processing | done | failed | failed_embed
  error_message TEXT,
  worker_id     TEXT,                                   -- set by processing worker, cleared on done
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_cb_ingestion_queue_status ON cb_ingestion_queue(status, queued_at);
```

### WAL-Style Semantics

- **Append-only insert:** new work items are always inserted; never overwrite.
- **Processing worker:** claims rows by setting `status = 'processing'` and `worker_id = <worker_uuid>` in an atomic UPDATE with `WHERE status = 'queued' AND retry_count < 5`.
- **On success:** UPDATE `status = 'done'`.
- **On failure:** UPDATE `retry_count = retry_count + 1`; if `retry_count >= 5` → `status = 'failed'`; else `status = 'queued'` (re-queues for next retry cycle).
- **On embedding failure specifically:** `status = 'failed_embed'` — distinguishable from general failure.

### Auto-Retry on Reconnect

On connectivity-restored event (network change, app foreground): trigger worker resume to process all rows with `status = 'queued'`. Retry uses exponential backoff per row: `backoff = min(2^retry_count * 1s, 300s)`.

### Queue Depth

- **Config key:** `NCLAW_INGEST_QUEUE_MAX` — default `10000`
- **Warning threshold:** 80% of max (8000 rows) → emit user-visible warning: "Memory ingestion queue is nearly full. Some content may be delayed."
- **At max:** new items are rejected with a logged ERROR; user notification emitted.

---

## Failure Scenarios

### 1. Embedding API Down

**Trigger:** TEI sidecar returns non-200 / connection refused, AND ONNX fallback is unavailable.

**Behavior:**
1. Chunk is inserted into `cb_ingestion_queue` with `status = 'queued'`.
2. Retry up to `NCLAW_EMBED_MAX_RETRIES` (default 3) with exponential backoff.
3. After max retries: `status = 'failed_embed'`; emit WARNING to user dashboard.
4. On TEI recovery: worker resume processes `status = 'queued'` rows.

**Data loss:** none — raw content persisted in `raw_content JSONB`.

### 2. Disk Full

**Trigger:** SQLite / Postgres write fails with ENOSPC or equivalent.

**Behavior:**
1. Ingestion is blocked — all new inserts fail.
2. User-visible notification: "Disk full — memory ingestion paused."
3. WAL queue is preserved (already written before the disk-full condition hit, or rejected if disk was already full before the write).
4. No data loss for already-queued items; new items since the disk-full event are not ingested until space is freed.

**Recovery:** user frees disk space → worker resumes automatically.

### 3. Duplicate Ingest

**Trigger:** same `(source_type, source_id, chunk_seq, chunk_text)` submitted twice.

**Behavior:**
1. Dedupe hash matches existing `cb_embeddings` row.
2. Skip re-embedding; `UPDATE ingested_at = NOW()` on the existing row.
3. Log INFO: `"dedupe hit: source_type={}, source_id={}, chunk_seq={}"`.
4. No duplicate vector written.

**Data loss:** none.

### 4. Out-of-Order Chunks

**Trigger:** chunks for a `source_id` arrive in non-sequential `chunk_seq` order (e.g., chunk 3 before chunk 1).

**Behavior:**
1. Chunks are accepted unconditionally by chunk_seq value.
2. Deduplication is per-chunk (SHA-256 includes `chunk_seq`), so no false collision.
3. Retrieval always sorts by `chunk_seq ASC` — ordering is applied at query time, not ingest time.
4. No error, no special handling; the pipeline is inherently order-independent.

---

## Integration Points

### With T01 (cb_* Schema)

All adapters write to:
- `cb_embeddings`: each chunk's embedding, chunk_text (post-redaction), chunk_seq, token_count, source_type, source_id, entity_type, entity_id FK, pii_redacted, dedupe_hash
- `cb_conversations`, `cb_facts`, `cb_decisions`, `cb_entities`, `cb_topics`: entity rows created by adapter before embedding; `entity_id` FK on `cb_embeddings` links back

### With T02 (hybrid_retrieve)

`hybrid_retrieve()` queries `cb_embeddings` by vector + tsvector. Dedupe hash must be a queryable column (TEXT, indexed). Retrieval assumes `chunk_seq ASC` ordering for context reconstruction.

### With T03 (Relationship Graph Extraction)

Graph extraction triggers **post-ingestion** — after the embedding is stored in `cb_embeddings`, not mid-pipeline. The ingestion pipeline fires an event / inserts a work item for the graph extractor; it does not block on graph extraction completion.

---

## Config Key Reference

| Key | Default | Description |
|---|---|---|
| `NCLAW_CHUNK_MAX_TOKENS` | `512` | Maximum tokens per chunk |
| `NCLAW_CHUNK_OVERLAP_TOKENS` | `64` | Overlap tokens between adjacent chunks |
| `NCLAW_EMBED_BATCH_SIZE` | `32` | Chunks per TEI embedding request |
| `NCLAW_EMBED_MAX_RETRIES` | `3` | Max embedding retry attempts before dead-letter |
| `NCLAW_EMBED_ONNX_PATH` | `""` (unset) | Path to local BGE-M3 ONNX model; empty = no local fallback |
| `NCLAW_INGEST_QUEUE_MAX` | `10000` | Max cb_ingestion_queue depth before rejection |

---

## SPORT References

- `F-MASTER.md` — rows: `cb_ingestion_queue`, `cb_sync_state` (status = planned, phase = P1-E3-W6-S06-T04)
- `REGISTRY-SERVICES.md` — `memory-ingestion-pipeline` service entry
- `nclaw/.github/wiki/architecture/semantic-brain-schema.md` — base schema (T01)

## See Also

- `nclaw/.github/wiki/architecture/semantic-brain-schema.md` — cb_* table DDL (T01)
- `nclaw/.github/wiki/architecture/retrieval.md` — hybrid retrieval (T02) — to be created
- `nclaw/.github/wiki/architecture/relationship-graph.md` — graph extraction (T03) — to be created
- ADR-005: pgvector + tsvector + RRF retrieval strategy
- ADR-006: LLM gateway pool key cap and embedding lane routing
