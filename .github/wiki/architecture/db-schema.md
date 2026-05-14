# nClaw Local Database Schema v1 (P101)

## Overview

nClaw maintains a local-first database on each device (pglite on desktop, SQLite on mobile) that mirrors the server's `np_*` tables. This schema is the canonical local-first cache: reads never block the network, writes go local immediately and sync asynchronously.

## Schema Tables

### Core Data Tables

**`np_topics`** — conversation topics (auto-detected or user-created)
- `id` UUID primary key
- `path` LTREE (pg) / TEXT (sqlite) — hierarchical path (e.g., `work.projects.proposal`)
- `title` — topic label
- `parent_id` — reference to parent topic
- `summary` — brief topic summary
- `source_account_id` — multi-app isolation (default: `'primary'`)
- Indexes: `path` (GIST on pg, B-tree on sqlite), `(source_account_id, parent_id)`

**`np_messages`** — individual turns in conversations
- `id` UUID primary key
- `topic_id` — foreign key to `np_topics`
- `role` — one of `'user'`, `'assistant'`, `'system'`, `'tool'`
- `content` — message text or ciphertext
- `metadata` — JSONB (pg) / TEXT (sqlite) — optional fields (tool_call_id, token_count, model, etc.)
- `source_account_id` — multi-app isolation
- Index: `(topic_id, created_at)`

**`np_memories`** — extracted facts and preferences
- `id` UUID primary key
- `kind` — one of `'fact'`, `'decision'`, `'preference'`, `'entity_ref'`
- `content` — memory text
- `confidence` — float [0.0, 1.0] — certainty score
- `valid_from`, `valid_until` — temporal validity window
- `metadata` — JSONB / TEXT — tags, source_message_id, etc.
- `source_account_id` — multi-app isolation
- Index: `(kind, source_account_id)`

**`np_entities`** — named entities and relationships
- `id` UUID primary key
- `kind` — entity type (e.g., `'person'`, `'project'`, `'decision'`)
- `name` — entity name
- `metadata` — JSONB / TEXT — properties
- `source_account_id` — multi-app isolation
- Unique constraint: `(kind, name, source_account_id)`

**`np_embeddings`** — vector embeddings for semantic search
- `id` UUID primary key
- `target_kind` — what is embedded (e.g., `'message'`, `'memory'`, `'topic_summary'`)
- `target_id` — UUID of the target entity
- `model_id` — embedding model name (e.g., `'text-embedding-3-small'`)
- `dimension` — vector dimensionality (e.g., 1536)
- `embedding` — VECTOR on pg, BLOB (via sqlite-vec) on mobile
- `source_account_id` — multi-app isolation
- Index: `(target_kind, target_id)`

### Device-Local Tables

**`sync_queue`** — events pending sync to server
- `event_id` UUID primary key
- `payload` — JSONB / TEXT — event envelope
- `enqueued_at` — when event was queued
- `attempts` — retry count
- `next_attempt_at` — when to retry
- Not synced to server; local-only queue

**`device_meta`** — device-level metadata
- `key` TEXT primary key
- `value` — JSONB / TEXT
- Tracks: `schema_version`, `device_id`, `last_sync_hlc`
- Pre-populated with defaults

**`migrations`** — schema versioning
- `version` INTEGER primary key
- `name` — migration name
- `applied_at` — when applied
- Single row per version; prevents re-applying migrations

## Multi-App Isolation

The `source_account_id` column separates nClaw's data from other apps running on the same nSelf backend. Within a single nSelf deploy (one Postgres, one Hasura), multiple apps can co-exist. The column is NOT cloud multi-tenancy (that uses `tenant_id` on the server — see PPI Multi-Tenant Convention Wall). Locally, `source_account_id` defaults to `'primary'` and is always enforced at query time.

## Variants

**PostgreSQL (pglite, desktop):** Full-featured variant with GIST indexes, JSONB, VECTOR, and LTREE.

**SQLite (mobile):** Simplified variant using TEXT for paths/JSON, B-tree indexes, and BLOB for embeddings (sqlite-vec handles vector ops).

Both variants are semantically equivalent; syntax and storage differ per engine. The Rust `schema.rs` module holds both as `include_str!` constants.

## Source of Truth

Full sync protocol semantics (event envelopes, HLC ordering, LWW conflict resolution): `nclaw/protocol/sync-protocol.md`

Server schema and Hasura definitions: `plugins-pro/nself-sync/`
