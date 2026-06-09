-- nClaw semantic brain tables (P1-E3-W6-S06-T01)
-- PostgreSQL / pglite variant.
-- Scope: cb_* tables for local semantic memory (conversations, facts, decisions,
--   entities, topics, embeddings). NOT synced to server (local_only=true default).
-- Extension Dependencies:
--   - pgvector >= 0.5.0 (HNSW support, vector FLOAT4[], IVFFlat index)
--   - Must be installed before this migration runs.
-- See: nclaw/.github/wiki/architecture/semantic-brain-schema.md
-- See: ADR-005 (pgvector + tsvector + RRF retrieval), ADR-006 (AI gateway embedding lane)

-- ─── Extension prerequisite ──────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS vector;

-- Version guard: pgvector >= 0.5.0 required for HNSW index support (ADR-005)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension
    WHERE extname = 'vector'
      AND extversion::numeric >= 0.5
  ) THEN
    RAISE EXCEPTION
      'pgvector >= 0.5.0 required (HNSW support). Current version is too old. '
      'Please upgrade pgvector before running this migration. (LEDGER §A / MAPS §Table/Column Registry)';
  END IF;
END $$;

-- ─── RLS / workspace isolation note ─────────────────────────────────────────
-- RLS GUC key (MAPS canonical): current_setting('app.workspace_id')::uuid
-- NOT 'hasura.user'. Any RLS policy on cb_* tables MUST use app.workspace_id.

-- ─── cb_conversations ────────────────────────────────────────────────────────
-- Represents a conversation session stored locally. Maps to np_messages at the
-- topic level. Local-only: never synced to the nSelf server.
CREATE TABLE IF NOT EXISTS cb_conversations (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT        NOT NULL DEFAULT '',
    summary         TEXT        NULL,
    -- Provenance
    source_type     TEXT        NOT NULL DEFAULT 'user',  -- 'user'|'import'|'api'|'crd'
    source_id       TEXT        NOT NULL DEFAULT '',       -- originating entity ID (e.g., topic_id)
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Privacy
    local_only      BOOLEAN     NOT NULL DEFAULT true,     -- never sync this row to cloud
    pii_redacted    BOOLEAN     NOT NULL DEFAULT false,    -- chunk_text already redacted
    -- Soft-delete
    deleted_at      TIMESTAMPTZ NULL,
    -- Standard timestamps
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Workspace isolation (multi-app isolation — NOT cloud multi-tenancy)
    source_account_id TEXT      NOT NULL DEFAULT 'primary'
);

CREATE INDEX IF NOT EXISTS cb_conversations_account ON cb_conversations (source_account_id, deleted_at);
CREATE INDEX IF NOT EXISTS cb_conversations_source ON cb_conversations (source_type, source_id);

-- ─── cb_facts ────────────────────────────────────────────────────────────────
-- Extracted atomic facts from conversations or external ingestion.
CREATE TABLE IF NOT EXISTS cb_facts (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID        NULL REFERENCES cb_conversations(id) ON DELETE SET NULL,
    content         TEXT        NOT NULL,
    confidence      REAL        NOT NULL DEFAULT 1.0 CHECK (confidence >= 0.0 AND confidence <= 1.0),
    valid_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until     TIMESTAMPTZ NULL,
    metadata        JSONB       NOT NULL DEFAULT '{}',
    -- Provenance
    source_type     TEXT        NOT NULL DEFAULT 'extraction', -- 'extraction'|'user'|'import'
    source_id       TEXT        NOT NULL DEFAULT '',
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Privacy
    local_only      BOOLEAN     NOT NULL DEFAULT true,
    pii_redacted    BOOLEAN     NOT NULL DEFAULT false,
    -- Soft-delete
    deleted_at      TIMESTAMPTZ NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT      NOT NULL DEFAULT 'primary'
);

CREATE INDEX IF NOT EXISTS cb_facts_conversation ON cb_facts (conversation_id, deleted_at);
CREATE INDEX IF NOT EXISTS cb_facts_account ON cb_facts (source_account_id, deleted_at);

-- ─── cb_decisions ────────────────────────────────────────────────────────────
-- Tracked decisions captured during conversations.
CREATE TABLE IF NOT EXISTS cb_decisions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID        NULL REFERENCES cb_conversations(id) ON DELETE SET NULL,
    content         TEXT        NOT NULL,
    rationale       TEXT        NULL,
    status          TEXT        NOT NULL DEFAULT 'open' CHECK (status IN ('open','superseded','revoked')),
    superseded_by   UUID        NULL REFERENCES cb_decisions(id) ON DELETE SET NULL,
    metadata        JSONB       NOT NULL DEFAULT '{}',
    -- Provenance
    source_type     TEXT        NOT NULL DEFAULT 'extraction',
    source_id       TEXT        NOT NULL DEFAULT '',
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Privacy
    local_only      BOOLEAN     NOT NULL DEFAULT true,
    pii_redacted    BOOLEAN     NOT NULL DEFAULT false,
    -- Soft-delete
    deleted_at      TIMESTAMPTZ NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT      NOT NULL DEFAULT 'primary'
);

CREATE INDEX IF NOT EXISTS cb_decisions_conversation ON cb_decisions (conversation_id, deleted_at);
CREATE INDEX IF NOT EXISTS cb_decisions_status ON cb_decisions (status, source_account_id);

-- ─── cb_entities ─────────────────────────────────────────────────────────────
-- Named entities extracted from conversations (people, projects, places, etc.).
CREATE TABLE IF NOT EXISTS cb_entities (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    kind            TEXT        NOT NULL,   -- 'person'|'project'|'place'|'concept'|...
    name            TEXT        NOT NULL,
    canonical_name  TEXT        NULL,       -- normalized form for dedup
    metadata        JSONB       NOT NULL DEFAULT '{}',
    -- Provenance
    source_type     TEXT        NOT NULL DEFAULT 'extraction',
    source_id       TEXT        NOT NULL DEFAULT '',
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Privacy
    local_only      BOOLEAN     NOT NULL DEFAULT true,
    pii_redacted    BOOLEAN     NOT NULL DEFAULT false,
    -- Soft-delete
    deleted_at      TIMESTAMPTZ NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT      NOT NULL DEFAULT 'primary',
    UNIQUE (kind, name, source_account_id)
);

CREATE INDEX IF NOT EXISTS cb_entities_kind ON cb_entities (kind, source_account_id, deleted_at);
CREATE INDEX IF NOT EXISTS cb_entities_canonical ON cb_entities (canonical_name, source_account_id);

-- ─── cb_topics ───────────────────────────────────────────────────────────────
-- Semantic topics extracted or inferred from the conversation corpus.
CREATE TABLE IF NOT EXISTS cb_topics (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT        NOT NULL,
    summary         TEXT        NULL,
    tags            TEXT[]      NOT NULL DEFAULT '{}',
    metadata        JSONB       NOT NULL DEFAULT '{}',
    -- Provenance
    source_type     TEXT        NOT NULL DEFAULT 'inference',
    source_id       TEXT        NOT NULL DEFAULT '',
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Privacy
    local_only      BOOLEAN     NOT NULL DEFAULT true,
    pii_redacted    BOOLEAN     NOT NULL DEFAULT false,
    -- Soft-delete
    deleted_at      TIMESTAMPTZ NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT      NOT NULL DEFAULT 'primary'
);

CREATE INDEX IF NOT EXISTS cb_topics_account ON cb_topics (source_account_id, deleted_at);
CREATE INDEX IF NOT EXISTS cb_topics_tags ON cb_topics USING gin (tags);

-- ─── cb_embeddings (PARTITIONED by ingested_at) ──────────────────────────────
-- Vector embeddings for semantic retrieval. Partitioned monthly by ingested_at.
-- Retention: configurable via NCLAW_EMBEDDING_RETENTION_DAYS (default 180 days).
--   Cleanup job spec: a daily cron (implemented in T04 ingestion pipeline) should run:
--     DELETE FROM cb_embeddings
--     WHERE ingested_at < now() - (current_setting('nclaw.embedding_retention_days', true)::int
--                                   DEFAULT 180) * INTERVAL '1 day';
--   Alternatively: DROP PARTITION for partitions older than the retention window.
-- Vector dimension: 1024 (ADR-005 nclaw preset — BGE-M3 via TEI; openai text-embedding-3-large fallback)
-- Privacy: chunk_text is written ONLY after T04 redaction pass. pii_redacted=true means
--   the redaction pass has run. Never persist raw PII in chunk_text.
CREATE TABLE IF NOT EXISTS cb_embeddings (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Embedding vector (1024-dim FLOAT4, pgvector, ADR-005 nclaw preset)
    model_id        TEXT        NOT NULL,   -- e.g. 'bge-m3'|'openai/text-embedding-3-large'
    vector          FLOAT4[]    NOT NULL,   -- 1024-dim per ADR-005; MUST have array_length=1024
    -- Text chunk
    chunk_text      TEXT        NOT NULL,   -- plaintext AFTER redaction pass (T04)
    chunk_seq       INT         NOT NULL DEFAULT 0,  -- sequence within parent for ordered retrieval
    token_count     INT         NOT NULL DEFAULT 0,
    -- Parent entity reference (polymorphic FK; entity_type identifies the cb_* table)
    entity_type     TEXT        NOT NULL,   -- 'cb_conversations'|'cb_facts'|'cb_decisions'|'cb_entities'|'cb_topics'
    entity_id       UUID        NOT NULL,
    -- Provenance
    source_type     TEXT        NOT NULL DEFAULT 'ingestion',
    source_id       TEXT        NOT NULL DEFAULT '',
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Privacy
    local_only      BOOLEAN     NOT NULL DEFAULT true,
    pii_redacted    BOOLEAN     NOT NULL DEFAULT false,  -- chunk_text already redacted when true
    -- Soft-delete
    deleted_at      TIMESTAMPTZ NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT      NOT NULL DEFAULT 'primary',
    -- tsvector for full-text search (GIN-indexed; see below)
    -- Strategy: GENERATED ALWAYS AS (chosen over trigger for atomicity + no drift risk)
    -- Two language configs:
    --   'english' for natural language prose chunks (document content, summaries)
    --   'simple'  for code identifier tokens (function names, variable names)
    -- We store a combined tsvector weighted A (english) + B (simple identifiers).
    -- The simple-config tokens are upweighted for identifier-exact matching in code retrieval.
    content_tsv     TSVECTOR    GENERATED ALWAYS AS (
                        setweight(to_tsvector('english', coalesce(chunk_text, '')), 'A') ||
                        setweight(to_tsvector('simple',  coalesce(chunk_text, '')), 'B')
                    ) STORED
) PARTITION BY RANGE (ingested_at);

-- ─── Monthly partitions (initial year 2025-2026) ─────────────────────────────
-- Build agents creating new partitions follow the pattern: cb_embeddings_YYYY_MM
-- Partitions beyond the retention window (default 180 days) are eligible for DROP.
CREATE TABLE IF NOT EXISTS cb_embeddings_2025_11
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2025_12
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2026_01
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2026_02
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2026_03
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2026_04
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2026_05
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_2026_06
    PARTITION OF cb_embeddings
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE TABLE IF NOT EXISTS cb_embeddings_default
    PARTITION OF cb_embeddings
    DEFAULT;

-- ─── Indexes on cb_embeddings ─────────────────────────────────────────────────
-- GIN index on the tsvector column for full-text search (English + simple config)
CREATE INDEX IF NOT EXISTS cb_embeddings_tsv_gin
    ON cb_embeddings USING gin (content_tsv);

-- IVFFlat vector index for 1024-dim cosine similarity (ADR-005 nclaw preset)
-- lists=100 is a reasonable default for up to ~1M embeddings; tune per volume.
-- NOTE: IVFFlat requires at least (lists * 2) rows to be effective.
CREATE INDEX IF NOT EXISTS cb_embeddings_vector_ivfflat
    ON cb_embeddings USING ivfflat (vector vector_cosine_ops)
    WITH (lists = 100);

-- Entity lookup index (used in JOIN for retrieval)
CREATE INDEX IF NOT EXISTS cb_embeddings_entity
    ON cb_embeddings (entity_type, entity_id, deleted_at);

-- Account + ingestion time (used for TTL cleanup queries)
CREATE INDEX IF NOT EXISTS cb_embeddings_account_ingested
    ON cb_embeddings (source_account_id, ingested_at)
    WHERE deleted_at IS NULL;

-- ─── Migration record ─────────────────────────────────────────────────────────
INSERT INTO migrations (version, name) VALUES (3, 'semantic_brain_tables')
ON CONFLICT (version) DO NOTHING;
