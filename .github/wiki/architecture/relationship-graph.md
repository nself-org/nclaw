# nClaw Relationship Graph — Architecture Spec

**Source ticket:** P1-E3-W6-S06-T03  
**Status:** planned (P1 Build target)  
**Depends on:** T01 (cb_* entity tables), T02 (hybrid retrieval)  
**Blocks:** T04 (ingestion pipeline), E5/W13 agent orchestration layer

---

## Overview

The relationship graph layer stores typed connections between named entities extracted from the nClaw semantic brain (conversations, facts, decisions). It enables queries like "what projects depend on this library?", "who authored this decision?", and "what topics connect these two people?".

Extraction is incremental: every new row in `cb_facts`, `cb_conversations`, or `cb_decisions` triggers a lightweight NER + LLM reasoning pass that produces node and edge candidates. High-confidence candidates are auto-accepted; uncertain ones queue for human review.

---

## 1. Node Taxonomy

Seven node types. Every node shares a mandatory field set plus a per-type optional JSONB metadata shape.

### 1.1 Mandatory Fields (all node types)

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key, generated |
| `node_type` | TEXT | Enum: Person, Project, Repo, Account, Document, Task, Decision, Event |
| `label` | TEXT | Human-readable name (e.g., "Ali Salaah", "nclaw") |
| `source_entity_id` | UUID | FK to the originating entity row (nullable — see §3.2) |
| `source_entity_table` | TEXT | Which table the FK references (cb_facts, cb_conversations, cb_entities, etc.) |
| `confidence` | FLOAT4 | Range 0.0–1.0. CHECK constraint enforced. |
| `review_status` | TEXT | `auto_accepted` \| `pending_review` \| `rejected` |
| `created_at` | TIMESTAMPTZ | Extraction timestamp |
| `updated_at` | TIMESTAMPTZ | Last modification |

### 1.2 Per-Type JSONB Metadata Schema

| Node Type | Optional Metadata Fields |
|---|---|
| **Person** | `email TEXT`, `github_handle TEXT`, `display_name TEXT` |
| **Project** | `repo_url TEXT`, `description TEXT`, `status TEXT` |
| **Repo** | `clone_url TEXT`, `language TEXT`, `default_branch TEXT` |
| **Account** | `provider TEXT` (github/google/etc.), `account_id TEXT` |
| **Document** | `file_path TEXT`, `mime_type TEXT`, `title TEXT` |
| **Task** | `task_id TEXT`, `status TEXT` (open/closed), `source_system TEXT` |
| **Decision** | `decision_text TEXT`, `rationale TEXT`, `decided_at TIMESTAMPTZ` |
| **Event** | `event_type TEXT`, `occurred_at TIMESTAMPTZ`, `location TEXT` |

`review_status` enum:
- `auto_accepted` — confidence ≥ 0.8; used immediately in graph queries
- `pending_review` — confidence < 0.8; held in correction queue; not included in live graph queries
- `rejected` — manually dismissed; retained for audit trail

---

## 2. Edge Taxonomy

Six edge types. Edges are directed by default; MENTIONS is bidirectional.

### 2.1 Mandatory Fields (all edge types)

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `edge_type` | TEXT | Enum: WORKS_ON, REFERENCES, AUTHORED_BY, DEPENDS_ON, MENTIONS, CAUSED_BY |
| `from_node_id` | UUID | FK → cb_graph_nodes.id |
| `to_node_id` | UUID | FK → cb_graph_nodes.id |
| `confidence` | FLOAT4 | CHECK (confidence >= 0.0 AND confidence <= 1.0) |
| `direction` | TEXT | `directed` \| `bidirectional` |
| `provenance_source` | TEXT | Format: `{extraction_pass}:{source_ticket}` e.g. `ner_pass_1:T03` |
| `extracted_at` | TIMESTAMPTZ | |
| `review_status` | TEXT | `auto_accepted` \| `pending_review` \| `rejected` |

### 2.2 Edge Type Reference

| Edge Type | Typical Subject | Typical Object | Direction | Notes |
|---|---|---|---|---|
| `WORKS_ON` | Person | Project / Repo | directed | A person contributes to a project |
| `REFERENCES` | Document / Task | Document / Repo / Decision | directed | One artifact cites another |
| `AUTHORED_BY` | Decision / Document | Person | directed | Authorship attribution |
| `DEPENDS_ON` | Project / Task / Repo | Project / Repo | directed | Software or task dependency |
| `MENTIONS` | any | any | **bidirectional** | Co-occurrence in same chunk |
| `CAUSED_BY` | Event / Decision | Event / Decision | directed | Causal chain |

### 2.3 Conflict Resolution Rule

When two extraction passes produce contradicting edges (same `from_node_id` + `to_node_id` + `edge_type` but different confidence):

1. **Higher confidence wins** — the higher-confidence edge is marked `auto_accepted`; the lower-confidence edge is set `rejected`.
2. **Equal confidence** — both edges inserted with `review_status = pending_review`; human reviewer resolves.
3. **Same pass, same confidence** — treat as a duplicate; keep one, discard the other.

An "already-accepted" edge that is contradicted by a new extraction pass follows the same rule: if new confidence > accepted confidence, the accepted edge is downgraded to `pending_review` and the new edge becomes `auto_accepted`. This ensures corrections from re-extract can propagate.

---

## 3. Entity Extraction Pipeline

### 3.1 Trigger

Incremental. The extraction pipeline fires for each new row inserted into:
- `cb_facts`
- `cb_conversations`
- `cb_decisions`

Triggered by T04 (ingestion pipeline). Not a background batch job by default; real-time extraction keeps latency for graph queries low.

### 3.2 Platform Split (ADR-005 / LEDGER §G)

| Platform | NER approach | LLM fallback |
|---|---|---|
| **Mobile** (Flutter/Dart) | Regex-only NER (no spaCy — no Python runtime on device) | ADR-006 fast lane (gemini-3.5-flash, ≤200 token prompt) for ambiguous cases |
| **Desktop** (Tauri 2 / Rust) | spaCy binding allowed for first-pass NER | Same: ADR-006 fast lane for ambiguous / high-value edge types |
| **Locked fallback (both)** | Regex-only | Falls back to regex if spaCy or LLM unavailable; never fails silent |

The regex NER patterns target:
- Person names (capitalized multi-word tokens)
- GitHub handles (`@username`, `github.com/handle`)
- URLs / repo clone paths
- Task references (`#123`, `JIRA-123`, `T-NN`)
- Dates and times (for Event nodes)

### 3.3 Confidence Threshold

| Confidence | Outcome |
|---|---|
| ≥ 0.8 | `review_status = auto_accepted` — node/edge added to live graph immediately |
| < 0.8 | `review_status = pending_review` — queued in `cb_graph_nodes` / `cb_graph_edges` but excluded from live graph queries |
| Manual dismiss | `review_status = rejected` — retained for audit, never shown |

### 3.4 Relation Extraction

**Co-occurrence rule:** if two entities appear in the same `cb_fact` or `cb_conversation` chunk, an edge of type `MENTIONS` is inferred:

```
confidence = min(0.5 + 0.1 * co_occurrence_count, 0.9)
```

**LLM structured prompt (high-value edge types):** for `DEPENDS_ON` and `CAUSED_BY`, a structured prompt is sent to ADR-006 fast lane (gemini-3.5-flash):

```
System: You are extracting dependency relationships from developer notes.
User: <chunk text>
Output: JSON { "edges": [ { "from": "<label>", "to": "<label>", "type": "DEPENDS_ON|CAUSED_BY", "confidence": 0.0-1.0 } ] }
```

Prompt ≤ 200 tokens (fast lane constraint). If the LLM call fails or times out, the extraction pass falls back to co-occurrence only.

---

## 4. Graph Storage Tables

### 4.1 `cb_graph_nodes` DDL

```sql
CREATE TABLE cb_graph_nodes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_type           TEXT NOT NULL,                          -- Person|Project|Repo|Account|Document|Task|Decision|Event
  label               TEXT NOT NULL,
  source_entity_id    UUID,                                   -- nullable: may reference rows across cb_* tables
  source_entity_table TEXT,                                   -- cb_facts|cb_conversations|cb_entities|cb_decisions|cb_topics
  metadata            JSONB NOT NULL DEFAULT '{}',
  confidence          FLOAT4 NOT NULL CHECK (confidence >= 0.0 AND confidence <= 1.0),
  review_status       TEXT NOT NULL DEFAULT 'pending_review'  -- auto_accepted|pending_review|rejected
                      CHECK (review_status IN ('auto_accepted', 'pending_review', 'rejected')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_graph_nodes_type       ON cb_graph_nodes (node_type);
CREATE INDEX idx_graph_nodes_label      ON cb_graph_nodes (label);
CREATE INDEX idx_graph_nodes_review     ON cb_graph_nodes (review_status);
CREATE INDEX idx_graph_nodes_source     ON cb_graph_nodes (source_entity_table, source_entity_id);
```

**ltree column (optional, desktop Postgres only):**  
For hierarchical traversal of DEPENDS_ON chains, an `ltree` path column may be added in a later migration:

```sql
ALTER TABLE cb_graph_nodes ADD COLUMN path LTREE;
CREATE INDEX idx_graph_nodes_path ON cb_graph_nodes USING GIST (path);
```

The ltree path encodes the ancestry chain (e.g., `nclaw.core.libnclaw`). This column is `NULL` when ltree is not populated.

### 4.2 `cb_graph_edges` DDL

```sql
CREATE TABLE cb_graph_edges (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  edge_type         TEXT NOT NULL,                            -- WORKS_ON|REFERENCES|AUTHORED_BY|DEPENDS_ON|MENTIONS|CAUSED_BY
  from_node_id      UUID NOT NULL REFERENCES cb_graph_nodes(id) ON DELETE CASCADE,
  to_node_id        UUID NOT NULL REFERENCES cb_graph_nodes(id) ON DELETE CASCADE,
  confidence        FLOAT4 NOT NULL CHECK (confidence >= 0.0 AND confidence <= 1.0),
  direction         TEXT NOT NULL DEFAULT 'directed'
                    CHECK (direction IN ('directed', 'bidirectional')),
  provenance_source TEXT NOT NULL,                            -- "{pass}:{source_ticket}"
  extracted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  review_status     TEXT NOT NULL DEFAULT 'pending_review'
                    CHECK (review_status IN ('auto_accepted', 'pending_review', 'rejected'))
);

CREATE INDEX idx_graph_edges_from_type  ON cb_graph_edges (from_node_id, edge_type);
CREATE INDEX idx_graph_edges_to_type    ON cb_graph_edges (to_node_id, edge_type);
CREATE INDEX idx_graph_edges_review     ON cb_graph_edges (review_status);
CREATE INDEX idx_graph_edges_type       ON cb_graph_edges (edge_type);
```

### 4.3 ltree vs Adjacency List — ADR Note

| Strategy | Best for | Trade-offs |
|---|---|---|
| **ltree** (preferred) | ≤ 100K nodes, hierarchical DEPENDS_ON chains, path queries | Requires path maintenance; GIST index; not available on SQLite (mobile) |
| **Adjacency list + recursive CTE** | > 100K nodes, any SQLite environment | No path maintenance overhead; recursive CTE performance degrades on wide graphs |

**Decision:** ltree preferred for nClaw desktop (Postgres) for ≤ 100K nodes. Mobile uses adjacency list (SQLite constraint). Both share the same `cb_graph_nodes` / `cb_graph_edges` schema; ltree `path` column is Postgres-only and ignored on mobile.

---

## 5. Update Strategy

### 5.1 Incremental (default)

- Fires per new `cb_facts` / `cb_conversations` / `cb_decisions` row (triggered from T04).
- Low latency. New entities and edges available in live graph queries within seconds.
- Conflict resolution runs immediately on insertion (§2.3).

### 5.2 Weekly Batch Re-extract

- Runs every Sunday at 02:00 local time (scheduled via cb_cron or plugin-cron).
- Purpose: catch relationship changes that result from corrected entities (human reviewer rejecting an auto-accepted node changes co-occurrence counts).
- Scope: re-processes all rows ingested in the prior 7 days that touched a `pending_review` or `rejected` node.
- Conflict resolution re-runs; higher-confidence result wins per §2.3.

### 5.3 Conflict with Auto-Accepted Edge

If a weekly batch extraction produces a new edge that contradicts an already `auto_accepted` edge:
- New confidence > accepted: downgrade accepted to `pending_review`, accept new.
- New confidence ≤ accepted: add new edge as `pending_review` for human review.
- Human reviewer resolves ties; winning edge is marked `auto_accepted`; loser `rejected`.

---

## 6. Example Graph Queries

### 6.1 Shortest Path Between Two Nodes

Uses a recursive CTE (adjacency list) or ltree `lquery` (if path column populated):

```sql
-- Adjacency list: shortest path from node_a to node_b, max 5 hops
WITH RECURSIVE path_search(node_id, path, depth) AS (
  SELECT from_node_id, ARRAY[from_node_id], 1
  FROM cb_graph_edges
  WHERE from_node_id = :node_a_id
    AND review_status = 'auto_accepted'
  UNION ALL
  SELECT e.to_node_id, ps.path || e.to_node_id, ps.depth + 1
  FROM cb_graph_edges e
  JOIN path_search ps ON e.from_node_id = ps.node_id
  WHERE ps.depth < 5
    AND NOT (e.to_node_id = ANY(ps.path))
    AND e.review_status = 'auto_accepted'
)
SELECT path, depth
FROM path_search
WHERE node_id = :node_b_id
ORDER BY depth
LIMIT 1;
```

Expected output: `path = [uuid_a, uuid_intermediate, uuid_b]`, `depth = 2`.

### 6.2 Neighbors of an Entity

```sql
SELECT
  n.*,
  e.edge_type,
  e.confidence,
  e.direction,
  CASE WHEN e.from_node_id = :target_id THEN 'outgoing' ELSE 'incoming' END AS edge_direction
FROM cb_graph_edges e
JOIN cb_graph_nodes n ON (
  CASE WHEN e.from_node_id = :target_id THEN e.to_node_id ELSE e.from_node_id END = n.id
)
WHERE (e.from_node_id = :target_id OR e.to_node_id = :target_id)
  AND e.review_status = 'auto_accepted'
ORDER BY e.confidence DESC
LIMIT 20;
```

Expected output: rows of `cb_graph_nodes` plus `edge_type`, `confidence`, `edge_direction` for the 20 highest-confidence neighbors.

### 6.3 Subgraph by Topic

```sql
SELECT DISTINCT n.*
FROM cb_graph_nodes n
JOIN cb_graph_edges e ON e.from_node_id = n.id OR e.to_node_id = n.id
WHERE n.source_entity_id IN (
  SELECT id FROM cb_facts WHERE topic_id = :topic_id
  UNION
  SELECT id FROM cb_conversations WHERE topic_id = :topic_id
)
  AND n.review_status = 'auto_accepted'
  AND e.review_status = 'auto_accepted';
```

Expected output: all `auto_accepted` graph nodes whose source entity is linked to the given topic, plus their connecting edges.

---

## 7. Human Correction Queue (Stub)

The `review_status` column on both tables is the queue mechanism. A future correction UI reads:

```sql
SELECT * FROM cb_graph_nodes
WHERE review_status = 'pending_review'
ORDER BY created_at
LIMIT 50;

SELECT * FROM cb_graph_edges
WHERE review_status = 'pending_review'
ORDER BY extracted_at
LIMIT 50;
```

Actions available to reviewer:
- **Accept** → `UPDATE ... SET review_status = 'auto_accepted'`
- **Reject** → `UPDATE ... SET review_status = 'rejected'`
- **Edit label / metadata** → `UPDATE cb_graph_nodes SET label = $1, metadata = $2, review_status = 'auto_accepted'`

The correction UX implementation is out of scope for this ticket (future sprint).

---

## 8. Integration Points

### 8.1 With T01 Entity Tables (cb_facts, cb_conversations, cb_decisions)

`cb_graph_nodes.source_entity_id` is a polymorphic FK: it references the row in whichever `cb_*` table was the extraction source. The `source_entity_table` column names the table. The five T01 entity tables that cb_graph_nodes may reference:

| `source_entity_table` | What the row represents |
|---|---|
| `cb_facts` | A specific extracted fact |
| `cb_conversations` | A conversation turn |
| `cb_decisions` | A tracked decision |
| `cb_entities` | An already-identified entity |
| `cb_topics` | A topic cluster |

### 8.2 With T02 Hybrid Retrieval

Graph query results can be fused with hybrid_retrieve() results via a re-ranking step. Example: after semantic search returns top-K document chunks, the caller may optionally expand the result with graph neighbors of any Person or Project nodes extracted from those chunks. This fusion is performed at application layer (not inside hybrid_retrieve()); the graph provides additive context, not a replacement retrieval path.

---

## 9. SPORT Registration

| Table | SPORT row | Status |
|---|---|---|
| `cb_graph_nodes` | F-MASTER.md — nClaw Semantic Brain section | 🔲 Planned (T03) |
| `cb_graph_edges` | F-MASTER.md — nClaw Semantic Brain section | 🔲 Planned (T03) |
| Graph entity taxonomy | master-inventories.md — Graph Entity Taxonomy section | 🔲 Planned (T03) |

---

## See Also

- `nclaw/.github/wiki/architecture/db-schema.md` — base cb_* entity tables (T01)
- `nclaw/.github/wiki/architecture/db-schema-versioning.md` — migration versioning policy
- `.claude/docs/architecture/nclaw-semantic-brain.md` — semantic brain overview
- `P1-BUILD-DECISIONS.md §G` — NER model choices (mobile=regex-only; desktop=spaCy+LLM)
- ADR-005 — BGE-M3 embedding lane
- ADR-006 — AI gateway fast lane (gemini-3.5-flash ≤200 token prompt)
