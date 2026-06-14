-- Migration 0090 — nclaw_user_memories + nclaw_memory_facts + nclaw_session_wal
-- Idempotent: all DDL uses IF NOT EXISTS.
-- Canonical: P2-E5 nclaw personal memory schema (T02).
--
-- Isolation: source_account_id TEXT (consumer multi-app pattern, NOT tenant_id).
-- Per PPI Convention Wall: nClaw is a Type-C consumer app sharing one nSelf deploy.
-- RLS GUC key: current_setting('app.source_account_id', true)
--   The `true` second arg returns NULL (not error) when GUC is unset — safe for
--   migration runners.
--
-- Tables:
--   nclaw_user_memories  — primary memory store, vector(1024) + BM25 tsvector
--   nclaw_memory_facts   — triple-store (subject/predicate/object) per memory
--   nclaw_session_wal    — WAL buffer for in-progress sessions before compaction
--
-- Reference: .claude/docs/nclaw-memory-architecture-spec.md §3 §4 §5

-- ── pgvector extension ────────────────────────────────────────────────────────
-- Guard is idempotent. Extension was first enabled in 0082 (clawde_chunks) but
-- this CREATE EXTENSION IF NOT EXISTS is safe to repeat on every migration run.
CREATE EXTENSION IF NOT EXISTS vector;

-- ── nclaw_user_memories ───────────────────────────────────────────────────────
-- Primary memory store for personal nClaw memory.
-- embedding: BGE-M3 1024-dim vectors (matches clawde_chunks precedent, ADR-005).
-- content_tsv: GENERATED tsvector for BM25 retrieval (canonical column name from P1).
-- namespace: e.g. 'personal/nclaw_<user_uuid>' — per spec §3.
-- memory_type: 'fact' (default), 'preference', 'event', 'summary', etc.
-- valid_from / valid_until: temporal validity for evolving facts.
CREATE TABLE IF NOT EXISTS nclaw_user_memories (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_account_id  TEXT        NOT NULL DEFAULT 'primary',
    user_id            UUID        NOT NULL,
    content            TEXT        NOT NULL,
    embedding          vector(1024),
    -- CANONICAL NAME: content_tsv (matches clawde_chunks P1 standard).
    content_tsv        TSVECTOR    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED,
    memory_type        TEXT        NOT NULL DEFAULT 'fact',
    namespace          TEXT        NOT NULL,
    valid_from         TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until        TIMESTAMPTZ,
    metadata           JSONB,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── nclaw_memory_facts ────────────────────────────────────────────────────────
-- Triple-store layer: one memory can produce multiple (subject, predicate, object)
-- fact triples extracted by WAL compaction. Confidence tracks extraction certainty.
-- Linked to nclaw_user_memories via FK with CASCADE on delete.
CREATE TABLE IF NOT EXISTS nclaw_memory_facts (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_id          UUID        NOT NULL REFERENCES nclaw_user_memories(id) ON DELETE CASCADE,
    source_account_id  TEXT        NOT NULL DEFAULT 'primary',
    user_id            UUID        NOT NULL,
    subject            TEXT        NOT NULL,
    predicate          TEXT        NOT NULL,
    object             TEXT        NOT NULL,
    confidence         FLOAT8      NOT NULL DEFAULT 1.0,
    valid_from         TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── nclaw_session_wal ─────────────────────────────────────────────────────────
-- WAL (write-ahead log) buffer for live sessions. Rows are appended per turn
-- (role: 'user' or 'assistant'). Nightly compaction (nself cron plugin) sets
-- compacted = true and promotes facts to nclaw_user_memories + nclaw_memory_facts.
-- session_id: caller-assigned opaque string (UUID or slug).
CREATE TABLE IF NOT EXISTS nclaw_session_wal (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_account_id  TEXT        NOT NULL DEFAULT 'primary',
    user_id            UUID        NOT NULL,
    session_id         TEXT        NOT NULL,
    role               TEXT        NOT NULL CHECK (role IN ('user', 'assistant')),
    content            TEXT        NOT NULL,
    compacted          BOOLEAN     NOT NULL DEFAULT false,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────

-- HNSW index on nclaw_user_memories.embedding for approximate nearest-neighbor
-- cosine-distance search (spec §2: m=16, ef_construction=64).
CREATE INDEX IF NOT EXISTS nclaw_user_memories_embedding_idx
    ON nclaw_user_memories
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- GIN index on nclaw_user_memories.content_tsv for BM25 full-text retrieval.
CREATE INDEX IF NOT EXISTS nclaw_memory_facts_tsv_idx
    ON nclaw_user_memories
    USING gin (content_tsv);

-- Supporting indexes for common query patterns.
CREATE INDEX IF NOT EXISTS nclaw_user_memories_user_namespace_idx
    ON nclaw_user_memories (source_account_id, user_id, namespace);

CREATE INDEX IF NOT EXISTS nclaw_memory_facts_memory_idx
    ON nclaw_memory_facts (memory_id);

CREATE INDEX IF NOT EXISTS nclaw_memory_facts_user_idx
    ON nclaw_memory_facts (source_account_id, user_id);

CREATE INDEX IF NOT EXISTS nclaw_session_wal_session_idx
    ON nclaw_session_wal (source_account_id, user_id, session_id, created_at DESC);

CREATE INDEX IF NOT EXISTS nclaw_session_wal_compacted_idx
    ON nclaw_session_wal (compacted, created_at)
    WHERE compacted = false;

-- ── Row-Level Security ────────────────────────────────────────────────────────
-- Isolation: app.source_account_id GUC (NOT app.workspace_id — this is consumer
-- isolation, not workspace isolation). Set per-connection by the gateway before
-- any query.

-- nclaw_user_memories
ALTER TABLE nclaw_user_memories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'nclaw_user_memories'
      AND policyname = 'nclaw_user_memories_isolation'
  ) THEN
    CREATE POLICY nclaw_user_memories_isolation ON nclaw_user_memories
      USING (source_account_id = current_setting('app.source_account_id', true));
  END IF;
END $$;

-- nclaw_memory_facts
ALTER TABLE nclaw_memory_facts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'nclaw_memory_facts'
      AND policyname = 'nclaw_memory_facts_isolation'
  ) THEN
    CREATE POLICY nclaw_memory_facts_isolation ON nclaw_memory_facts
      USING (source_account_id = current_setting('app.source_account_id', true));
  END IF;
END $$;

-- nclaw_session_wal
ALTER TABLE nclaw_session_wal ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'nclaw_session_wal'
      AND policyname = 'nclaw_session_wal_isolation'
  ) THEN
    CREATE POLICY nclaw_session_wal_isolation ON nclaw_session_wal
      USING (source_account_id = current_setting('app.source_account_id', true));
  END IF;
END $$;

-- ── Rollback ──────────────────────────────────────────────────────────────────
-- /* DOWN
-- DROP TABLE IF EXISTS nclaw_session_wal CASCADE;
-- DROP TABLE IF EXISTS nclaw_memory_facts CASCADE;
-- DROP TABLE IF EXISTS nclaw_user_memories CASCADE;
-- */
