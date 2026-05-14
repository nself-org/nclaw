-- nClaw local DB schema v1 (P101)
-- SQLite variant. Mirrors np_* tables from PostgreSQL schema.
-- Path is TEXT (dot-separated), JSON is TEXT (json1 extension), UUID is TEXT.

PRAGMA foreign_keys = ON;

-- Multi-app isolation (NOT cloud multi-tenancy)

CREATE TABLE IF NOT EXISTS np_topics (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL,
    title TEXT NOT NULL,
    parent_id TEXT NULL REFERENCES np_topics(id) ON DELETE CASCADE,
    summary TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    source_account_id TEXT NOT NULL DEFAULT 'primary',
    archived_at TEXT NULL
);
CREATE INDEX IF NOT EXISTS np_topics_path_idx ON np_topics (path);
CREATE INDEX IF NOT EXISTS np_topics_account_idx ON np_topics (source_account_id, parent_id);

CREATE TABLE IF NOT EXISTS np_messages (
    id TEXT PRIMARY KEY,
    topic_id TEXT NOT NULL REFERENCES np_topics(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user','assistant','system','tool')),
    content TEXT NOT NULL,
    created_at TEXT NOT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    source_account_id TEXT NOT NULL DEFAULT 'primary'
);
CREATE INDEX IF NOT EXISTS np_messages_topic_created_idx ON np_messages (topic_id, created_at);

CREATE TABLE IF NOT EXISTS np_memories (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('fact','decision','preference','entity_ref')),
    content TEXT NOT NULL,
    confidence REAL NOT NULL DEFAULT 1.0 CHECK (confidence >= 0.0 AND confidence <= 1.0),
    valid_from TEXT NOT NULL,
    valid_until TEXT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    source_account_id TEXT NOT NULL DEFAULT 'primary'
);
CREATE INDEX IF NOT EXISTS np_memories_kind_account_idx ON np_memories (kind, source_account_id);

CREATE TABLE IF NOT EXISTS np_entities (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    source_account_id TEXT NOT NULL DEFAULT 'primary',
    UNIQUE (kind, name, source_account_id)
);

CREATE TABLE IF NOT EXISTS np_embeddings (
    id TEXT PRIMARY KEY,
    target_kind TEXT NOT NULL,
    target_id TEXT NOT NULL,
    model_id TEXT NOT NULL,
    dimension INTEGER NOT NULL,
    embedding BLOB,
    created_at TEXT NOT NULL,
    source_account_id TEXT NOT NULL DEFAULT 'primary'
);
CREATE INDEX IF NOT EXISTS np_embeddings_target_idx ON np_embeddings (target_kind, target_id);

-- Device-local tables (NOT synced to server)

CREATE TABLE IF NOT EXISTS sync_queue (
    event_id TEXT PRIMARY KEY,
    payload TEXT NOT NULL,
    enqueued_at TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TEXT NULL
);
CREATE INDEX IF NOT EXISTS sync_queue_next_attempt_idx ON sync_queue (next_attempt_at);

CREATE TABLE IF NOT EXISTS device_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
INSERT OR IGNORE INTO device_meta (key, value, updated_at) VALUES
    ('schema_version', '"1"', datetime('now')),
    ('device_id', 'null', datetime('now')),
    ('last_sync_hlc', '"0"', datetime('now'));

CREATE TABLE IF NOT EXISTS migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TEXT NOT NULL
);
INSERT OR IGNORE INTO migrations (version, name, applied_at) VALUES
    (1, 'initial_schema', datetime('now'));
