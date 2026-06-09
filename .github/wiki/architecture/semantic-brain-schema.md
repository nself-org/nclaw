# nClaw Semantic Brain Schema

**Status:** Planned (P1-E3-W6-S06-T01)
**Migration:** `nclaw/core/migrations/0003_semantic_brain_tables.sql`
**ADRs:** ADR-005 (pgvector + tsvector + RRF), ADR-006 (AI gateway embedding lane)

---

## Overview

The `cb_*` tables form nClaw's **local semantic brain** — a device-local storage layer for semantic memory that augments the existing `np_*` conversation cache. While `np_*` tables mirror server state (topics, messages, memories, entities), the `cb_*` tables are purpose-built for local-first AI reasoning:

- Full-text search via `tsvector` GIN indexes
- Semantic search via pgvector (1024-dim FLOAT4, IVFFlat index)
- Provenance tracking (`source_type`, `source_id`, `ingested_at`) per row
- Privacy-first design: `local_only=true` by default, PII redaction enforced at ingestion
- Soft-delete pattern across all tables (`deleted_at TIMESTAMPTZ NULL`)

The `cb_*` tables are **never synced to the nSelf server**. The `np_*` tables handle server sync; the `cb_*` tables are the local AI working memory.

---

## Table Overview (ASCII diagram)

```
cb_conversations ──┬──< cb_facts       (conversation_id FK)
                   ├──< cb_decisions   (conversation_id FK)
                   └── (referenced by cb_embeddings.entity_id when entity_type='cb_conversations')

cb_entities ─────────── (referenced by cb_embeddings.entity_id when entity_type='cb_entities')
cb_topics ───────────── (referenced by cb_embeddings.entity_id when entity_type='cb_topics')
cb_facts ────────────── (referenced by cb_embeddings.entity_id when entity_type='cb_facts')
cb_decisions ────────── (referenced by cb_embeddings.entity_id when entity_type='cb_decisions')

cb_embeddings [PARTITIONED BY RANGE(ingested_at)]
  - entity_type + entity_id → polymorphic FK to any cb_* table
  - vector FLOAT4[1024] → pgvector IVFFlat (cosine)
  - content_tsv TSVECTOR  → GIN index (English + simple config)
```

---

## Table Descriptions

### cb_conversations

Conversation sessions stored locally. Maps conceptually to `np_topics` but is self-contained for local semantic use (does not require a server mirror). The ingestion pipeline (T04) creates one `cb_conversations` row per conversation and then chunks its content into `cb_embeddings`.

**Key columns:**

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | `gen_random_uuid()` |
| `title` | TEXT | Display title |
| `summary` | TEXT | LLM-generated summary |
| `source_type` | TEXT | `'user'`, `'import'`, `'api'`, `'crd'` |
| `source_id` | TEXT | Originating entity ID (e.g., `np_topics.id`) |
| `ingested_at` | TIMESTAMPTZ | When this conversation entered the semantic brain |
| `local_only` | BOOLEAN | Default `true` — never sync to cloud |
| `pii_redacted` | BOOLEAN | `true` when T04 redaction has run |
| `deleted_at` | TIMESTAMPTZ | Soft-delete; queries filter `WHERE deleted_at IS NULL` |

### cb_facts

Atomic facts extracted from conversations by the T04 ingestion pipeline.

**Key columns** (in addition to shared provenance/privacy/soft-delete pattern):

| Column | Type | Notes |
|---|---|---|
| `conversation_id` | UUID FK | `REFERENCES cb_conversations(id) ON DELETE SET NULL` |
| `content` | TEXT | The fact statement |
| `confidence` | REAL | [0.0, 1.0] extraction certainty |
| `valid_from` / `valid_until` | TIMESTAMPTZ | Temporal validity window |

### cb_decisions

Decisions captured during conversations. Supports supersession: a decision can be linked to the decision that replaced it via `superseded_by`.

**Key columns:**

| Column | Type | Notes |
|---|---|---|
| `conversation_id` | UUID FK | Origin conversation |
| `content` | TEXT | Decision statement |
| `rationale` | TEXT | Why this decision was made |
| `status` | TEXT | `'open'`, `'superseded'`, `'revoked'` |
| `superseded_by` | UUID FK | Points to replacement decision |

### cb_entities

Named entities (people, projects, places, concepts) extracted from conversations. Uses a unique constraint on `(kind, name, source_account_id)` to prevent duplicates.

**Key columns:**

| Column | Type | Notes |
|---|---|---|
| `kind` | TEXT | Entity type: `'person'`, `'project'`, `'place'`, `'concept'`, etc. |
| `name` | TEXT | Raw extracted name |
| `canonical_name` | TEXT | Normalized form for dedup and search |

### cb_topics

Semantic topics inferred or detected by the AI layer. Broader than `np_topics` (which are user-visible conversation branches); `cb_topics` are AI-inferred thematic clusters.

**Key columns:**

| Column | Type | Notes |
|---|---|---|
| `title` | TEXT | Topic label |
| `summary` | TEXT | Concise description |
| `tags` | TEXT[] | GIN-indexed keyword array |

### cb_embeddings (PARTITIONED)

The central semantic index. Each row is one chunk of text from a parent entity, embedded as a 1024-dim vector (BGE-M3 default, openai/text-embedding-3-large fallback per ADR-006).

**Vector column:**

```sql
vector FLOAT4[]   -- 1024-dim, pgvector FLOAT4, ADR-005 nclaw preset
```

- Indexed with `IVFFlat` (cosine similarity, `lists=100`)
- HNSW requires pgvector >= 0.5.0 (enforced by version check in migration)

**Full-text column (GIN-indexed):**

```sql
content_tsv TSVECTOR GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(chunk_text, '')), 'A') ||
    setweight(to_tsvector('simple',  coalesce(chunk_text, '')), 'B')
) STORED
```

**Language configuration decision:**

- `'english'` config: tokenizes natural language prose (ignores stop words, stems). Used for conversation content, summaries, fact statements. Weight `A` (highest).
- `'simple'` config: tokenizes without stemming (exact lowercased tokens). Used for code identifiers, package names, variable names. Weight `B`.
- Combined tsvector supports `tsquery` with both prose and identifier searches in a single GIN index scan. The RRF retrieval pipeline (T02) merges dense vector scores with BM25-via-tsvector scores.

**Partition strategy:**

Partitioned `BY RANGE (ingested_at)` with monthly boundaries. Initial partitions cover 2025-11 through 2026-06 plus a `DEFAULT` partition for overflow.

**Retention policy:**

```
Config key: NCLAW_EMBEDDING_RETENTION_DAYS (default: 180)
Cleanup job: implemented in T04 ingestion pipeline
Strategy: DELETE WHERE ingested_at < now() - interval '${days} days'
          OR: DROP PARTITION for partitions fully outside the retention window
```

---

## Privacy Model

All `cb_*` tables share a two-flag privacy model:

| Flag | Default | Semantics |
|---|---|---|
| `local_only` | `true` | Row is never eligible for server sync. The `nself-sync` plugin reads this flag; `local_only=true` rows are excluded from the sync queue. |
| `pii_redacted` | `false` | Becomes `true` after T04 ingestion pass. `chunk_text` in `cb_embeddings` is written **only** after redaction; raw PII (names, phone numbers, SSNs, etc.) must not appear in any persisted `chunk_text`. |

**Soft-delete:** All tables use `deleted_at TIMESTAMPTZ NULL`. Hard deletes are only performed by the retention cleanup job for expired embeddings.

**RLS workspace isolation:** Any RLS policy on `cb_*` tables must use `current_setting('app.workspace_id')::uuid` (MAPS canonical GUC key). Do **not** use `hasura.user` or any other GUC for these tables.

---

## Extension Dependencies

### pgvector

Required version: **>= 0.5.0** (for HNSW index support per ADR-005).

The migration enforces this with:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension
    WHERE extname = 'vector'
      AND extversion::numeric >= 0.5
  ) THEN
    RAISE EXCEPTION 'pgvector >= 0.5.0 required (HNSW support). ...';
  END IF;
END $$;
```

Install pgvector before applying this migration:
```bash
# Debian/Ubuntu
apt-get install postgresql-16-pgvector
# macOS (Homebrew)
brew install pgvector
```

---

## Relationship to np_* Tables

The `cb_*` and `np_*` tables serve different purposes:

| Layer | Tables | Purpose | Synced? |
|---|---|---|---|
| **Server mirror** | `np_topics`, `np_messages`, `np_memories`, `np_entities`, `np_embeddings` | Local cache of server state; read-heavy | Yes (via `nself-sync`) |
| **Semantic brain** | `cb_conversations`, `cb_facts`, `cb_decisions`, `cb_entities`, `cb_topics`, `cb_embeddings` | Local AI working memory; write on ingestion, read for reasoning | Never (local_only) |

The ingestion pipeline (T04) bridges the two layers: it reads `np_*` data, redacts PII, chunks text, embeds via TEI BGE-M3, and writes to `cb_*`.

---

## See Also

- `nclaw/core/migrations/0003_semantic_brain_tables.sql` — UP migration
- `nclaw/core/migrations/0003_semantic_brain_tables.down.sql` — DOWN migration
- `nclaw/.github/wiki/architecture/db-schema.md` — np_* tables reference
- `.claude/docs/architecture/nclaw-semantic-brain.md` — AI reference stub
- ADR-005 — pgvector + tsvector + RRF retrieval strategy
- ADR-006 — AI gateway embedding lane
- T02 — pgvector + tsvector RRF retrieval implementation
- T03 — relationship graph extraction
- T04 — memory ingestion and sync pipeline
