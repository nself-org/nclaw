-- nClaw semantic brain tables — DOWN migration (P1-E3-W6-S06-T01)
-- Reverses 0003_semantic_brain_tables.sql
-- Order: drop dependent tables first (embeddings has no FK children), then entity tables.

-- Drop cb_embeddings partitions first (must drop partitions before parent)
DROP TABLE IF EXISTS cb_embeddings_default;
DROP TABLE IF EXISTS cb_embeddings_2026_06;
DROP TABLE IF EXISTS cb_embeddings_2026_05;
DROP TABLE IF EXISTS cb_embeddings_2026_04;
DROP TABLE IF EXISTS cb_embeddings_2026_03;
DROP TABLE IF EXISTS cb_embeddings_2026_02;
DROP TABLE IF EXISTS cb_embeddings_2026_01;
DROP TABLE IF EXISTS cb_embeddings_2025_12;
DROP TABLE IF EXISTS cb_embeddings_2025_11;
DROP TABLE IF EXISTS cb_embeddings;

-- Drop entity tables (FK dependents before parents)
DROP TABLE IF EXISTS cb_decisions;
DROP TABLE IF EXISTS cb_facts;
DROP TABLE IF EXISTS cb_topics;
DROP TABLE IF EXISTS cb_entities;
DROP TABLE IF EXISTS cb_conversations;

-- Remove migration record
DELETE FROM migrations WHERE version = 3 AND name = 'semantic_brain_tables';
