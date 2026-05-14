-- nClaw indexes v1 (P101)
-- SQLite variant: sqlite-vec virtual table for embeddings.
-- FTS5 virtual table for memory full-text search.

-- SQLite does not have built-in vector types. The sqlite-vec extension
-- provides a virtual table interface for ANN (approximate nearest neighbor) search.
-- This is created lazily by the application per model_id as needed.
-- See sync-protocol.md for per-model vector embedding strategy.
CREATE VIRTUAL TABLE IF NOT EXISTS np_memories_fts USING fts5(
    content,
    content='np_memories',
    content_rowid='rowid'
);

-- Record this migration in the migrations table.
INSERT OR IGNORE INTO migrations (version, name) VALUES (2, 'indexes_v1');
