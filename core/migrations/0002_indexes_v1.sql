-- nClaw indexes v1 (P101)
-- HNSW vector index for semantic search (pgvector).
-- FTS5-equivalent GIN index for memory full-text search.
-- PostgreSQL / pglite variant.

-- Vector index on np_embeddings using HNSW (Hierarchical Navigable Small World).
-- Searches embeddings with cosine similarity. Dimension fixed to 768 for default models;
-- larger dimensions require separate indexes per model_id if needed.
CREATE INDEX IF NOT EXISTS np_embeddings_hnsw_768
    ON np_embeddings USING hnsw (embedding vector_cosine_ops)
    WHERE dimension = 768;

-- Memory text search GIN index.
-- Accelerates full-text search queries on memory content.
CREATE INDEX IF NOT EXISTS np_memories_content_gin
    ON np_memories USING gin (to_tsvector('english', content));

-- Record this migration in the migrations table.
INSERT INTO migrations (version, name) VALUES (2, 'indexes_v1')
ON CONFLICT (version) DO NOTHING;
