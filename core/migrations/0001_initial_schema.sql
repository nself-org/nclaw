-- nClaw local DB schema v1 (P101)
-- Mirrors server np_* tables. Source-of-truth: nclaw/protocol/sync-protocol.md.
-- PostgreSQL / pglite variant.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS ltree;
CREATE EXTENSION IF NOT EXISTS vector;

-- Multi-app isolation (NOT cloud multi-tenancy — see PPI Multi-Tenant Convention Wall)
-- source_account_id distinguishes nClaw's data from co-deployed apps' data within a single nself stack.

CREATE TABLE IF NOT EXISTS np_topics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    path LTREE NOT NULL,
    title TEXT NOT NULL,
    parent_id UUID NULL REFERENCES np_topics(id) ON DELETE CASCADE,
    summary TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT NOT NULL DEFAULT 'primary',
    archived_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS np_topics_path_gist ON np_topics USING GIST (path);
CREATE INDEX IF NOT EXISTS np_topics_account ON np_topics (source_account_id, parent_id);

CREATE TABLE IF NOT EXISTS np_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id UUID NOT NULL REFERENCES np_topics(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user','assistant','system','tool')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata JSONB NOT NULL DEFAULT '{}',
    source_account_id TEXT NOT NULL DEFAULT 'primary'
);
CREATE INDEX IF NOT EXISTS np_messages_topic_created ON np_messages (topic_id, created_at);

CREATE TABLE IF NOT EXISTS np_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind TEXT NOT NULL CHECK (kind IN ('fact','decision','preference','entity_ref')),
    content TEXT NOT NULL,
    confidence REAL NOT NULL DEFAULT 1.0 CHECK (confidence >= 0.0 AND confidence <= 1.0),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ NULL,
    metadata JSONB NOT NULL DEFAULT '{}',
    source_account_id TEXT NOT NULL DEFAULT 'primary'
);
CREATE INDEX IF NOT EXISTS np_memories_kind_account ON np_memories (kind, source_account_id);

CREATE TABLE IF NOT EXISTS np_entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}',
    source_account_id TEXT NOT NULL DEFAULT 'primary',
    UNIQUE (kind, name, source_account_id)
);

CREATE TABLE IF NOT EXISTS np_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_kind TEXT NOT NULL,
    target_id UUID NOT NULL,
    model_id TEXT NOT NULL,
    dimension INTEGER NOT NULL,
    embedding VECTOR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_account_id TEXT NOT NULL DEFAULT 'primary'
);
CREATE INDEX IF NOT EXISTS np_embeddings_target ON np_embeddings (target_kind, target_id);

-- Device-local tables (NOT synced to server)

CREATE TABLE IF NOT EXISTS sync_queue (
    event_id UUID PRIMARY KEY,
    payload JSONB NOT NULL,
    enqueued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS sync_queue_next_attempt ON sync_queue (next_attempt_at);

CREATE TABLE IF NOT EXISTS device_meta (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO device_meta (key, value) VALUES
    ('schema_version', '"1"'::JSONB),
    ('device_id', 'null'::JSONB),
    ('last_sync_hlc', '"0"'::JSONB)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO migrations (version, name) VALUES (1, 'initial_schema') ON CONFLICT DO NOTHING;
