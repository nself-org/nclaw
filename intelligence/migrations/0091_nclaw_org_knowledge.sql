-- Migration: 0091_nclaw_org_knowledge.sql
-- Ticket: P2-E5-W2-S3-T03
-- Tables: nclaw_org_knowledge, nclaw_org_facts, nclaw_agent_checkpoints
-- Spec: .claude/docs/nclaw-memory-architecture-spec.md §5 §12
--
-- Purpose:
--   Corporate namespace knowledge layer (nclaw_org_knowledge + nclaw_org_facts) and
--   LangGraph-style durable agent checkpoint table (nclaw_agent_checkpoints).
--   org_knowledge and org_facts use source_account_id for multi-app isolation and
--   org_slug for namespace partitioning within an app. RLS enforced on both.
--   nclaw_agent_checkpoints is a system table — no RLS; accessed by service account only.
--
-- Depends on: 0090_nclaw_user_memory.sql (pgvector extension must be enabled)

-- ============================================================
-- UP
-- ============================================================

-- ------------------------------------------------------------
-- Table: nclaw_org_knowledge
-- Corporate / team knowledge documents (runbooks, SOPs, wikis).
-- Partitioned by (source_account_id, org_slug) for multi-app and
-- multi-org isolation. RLS enforces source_account_id boundary.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nclaw_org_knowledge (
    id               UUID                        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_account_id TEXT                        NOT NULL DEFAULT 'primary',
    org_slug         TEXT                        NOT NULL,
    content          TEXT                        NOT NULL,
    embedding        vector(1024),
    content_tsv      tsvector                    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED,
    doc_type         TEXT                        NOT NULL DEFAULT 'runbook',
    source_ref       TEXT,
    chunk_index      INT                         DEFAULT 0,
    content_hash     TEXT,
    valid_from       TIMESTAMPTZ                 NOT NULL DEFAULT now(),
    valid_until      TIMESTAMPTZ,
    metadata         JSONB,
    created_at       TIMESTAMPTZ                 NOT NULL DEFAULT now()
);

-- HNSW vector index for approximate nearest-neighbour search
CREATE INDEX nclaw_org_knowledge_embedding_idx
    ON nclaw_org_knowledge
    USING hnsw (embedding vector_cosine_ops);

-- GIN full-text search index
CREATE INDEX nclaw_org_knowledge_content_tsv_idx
    ON nclaw_org_knowledge
    USING gin (content_tsv);

-- Composite index for namespace-scoped queries
CREATE INDEX nclaw_org_knowledge_org_slug_idx
    ON nclaw_org_knowledge (source_account_id, org_slug);

-- Row-level security: enforce app-level source_account_id boundary
ALTER TABLE nclaw_org_knowledge ENABLE ROW LEVEL SECURITY;

CREATE POLICY nclaw_org_knowledge_source_isolation
    ON nclaw_org_knowledge
    USING (source_account_id = current_setting('app.source_account_id', true));

-- ------------------------------------------------------------
-- Table: nclaw_org_facts
-- RDF-style triple store linked to org knowledge documents.
-- Enables structured fact retrieval alongside semantic search.
-- RLS mirrors nclaw_org_knowledge using source_account_id.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nclaw_org_facts (
    id               UUID                        PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_id     UUID                        REFERENCES nclaw_org_knowledge(id) ON DELETE CASCADE,
    source_account_id TEXT                        NOT NULL DEFAULT 'primary',
    org_slug         TEXT                        NOT NULL,
    subject          TEXT                        NOT NULL,
    predicate        TEXT                        NOT NULL,
    object           TEXT                        NOT NULL,
    confidence       FLOAT8                      NOT NULL DEFAULT 1.0,
    valid_from       TIMESTAMPTZ                 NOT NULL DEFAULT now(),
    valid_until      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ                 NOT NULL DEFAULT now()
);

-- Index for fact lookups by knowledge document
CREATE INDEX nclaw_org_facts_knowledge_id_idx
    ON nclaw_org_facts (knowledge_id);

-- Index for namespace-scoped fact queries
CREATE INDEX nclaw_org_facts_org_slug_idx
    ON nclaw_org_facts (source_account_id, org_slug);

-- Row-level security: enforce app-level source_account_id boundary
ALTER TABLE nclaw_org_facts ENABLE ROW LEVEL SECURITY;

CREATE POLICY nclaw_org_facts_source_isolation
    ON nclaw_org_facts
    USING (source_account_id = current_setting('app.source_account_id', true));

-- ------------------------------------------------------------
-- Table: nclaw_agent_checkpoints
-- LangGraph interrupt() checkpoint store for durable agent state.
-- Stores serialized graph snapshots so agents can resume after
-- failure, restart, or human-approval delays.
-- NO RLS — system table, accessed by service account only.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nclaw_agent_checkpoints (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id               TEXT        NOT NULL,
    checkpoint_id           TEXT        NOT NULL,
    agent_role              TEXT        NOT NULL,
    graph_state             JSONB       NOT NULL,
    status                  TEXT        NOT NULL DEFAULT 'active'
                                        CHECK (status IN ('active','awaiting_approval','completed','failed')),
    initiated_by_user_id    UUID,
    approval_channel        TEXT        DEFAULT 'telegram',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (thread_id, checkpoint_id)
);

-- Index for active checkpoint lookups by thread
CREATE INDEX nclaw_agent_checkpoints_thread_status_idx
    ON nclaw_agent_checkpoints (thread_id, status);

-- ============================================================
-- DOWN
-- ============================================================

-- Drop in dependency order: facts + checkpoints first, then knowledge
-- (nclaw_org_facts has FK → nclaw_org_knowledge; CASCADE handles it)

-- DROP TABLE IF EXISTS nclaw_agent_checkpoints CASCADE;
-- DROP TABLE IF EXISTS nclaw_org_facts CASCADE;
-- DROP TABLE IF EXISTS nclaw_org_knowledge CASCADE;
