# nClaw Hybrid Retrieval Pipeline

**Spec version:** P1-E3-W6-S06-T02 (design only; runtime implementation in E5/W11)
**ADR authority:** ADR-005 (retrieval strategy), ADR-006 (LLM gateway lanes)
**Preset:** nclaw — dense + lexical + reranker only (no sparse, no ColBERT)

---

## Overview

nClaw uses a three-lane hybrid retrieval pipeline to surface the most relevant chunks from the local semantic brain. The pipeline fuses dense vector similarity and lexical full-text search via Reciprocal Rank Fusion (RRF), then optionally re-ranks the top results using a cross-encoder reranker.

```
User query
    │
    ├── [Embed] TEI BGE-M3 (1024-dim) ──────────────────────────────────┐
    │                                                                   │
    ├── [Privacy/scope pre-filter] ─────────────────────────────────────┤
    │                                                                   ▼
    │                                                      Dense lane (pgvector ANN)
    │                                                      Lexical lane (tsvector GIN)
    │                                                                   │
    ├── [RRF fusion] score = Σ 1/(k + rank_i), k=60 ────────────────────┤
    │                                                                   │
    ├── [Freshness boost] multiply by recency_factor ───────────────────┤
    │                                                                   │
    └── [Re-ranker] BGE Reranker v2-m3 via TEI /rerank ────────────────▶ ranked results
```

---

## 1. Privacy and Scope Pre-filter

Applied **before** ANN search to enforce isolation.

```sql
WHERE local_only = true
  AND source_account_id IN (:allowed_accounts)
  AND topic_id IN (:allowed_topics)
```

- `local_only = true` — excludes chunks marked for cloud-only storage.
- `source_account_id IN (...)` — enforces multi-app isolation (nSelf Multi-Tenant Convention Wall).
- `topic_id IN (...)` — limits retrieval to topics the caller is authorized to read.

All three conditions are ANDed and applied in a single SQL WHERE clause before the ANN index scan.

---

## 2. Dense Vector Search

**Table:** `cb_embeddings`
**Column:** `vector` (pgvector FLOAT4, 1024-dim)
**Metric:** Cosine similarity (L2-normalized vectors → inner product equivalent)
**Index:** IVFFlat (`lists=100`)

### Query flow

1. Embed the user query via ADR-006 embedding lane:
   `Provider.Embed(ctx, queryText, expectedDim=1024)` — TEI BGE-M3 primary, OpenAI `text-embedding-3-large` fallback.
2. Run ANN scan with pre-filter (§1):
   ```sql
   SELECT id, chunk_text, ingested_at, topic_id, source_account_id,
          1 - (vector <=> :query_vector) AS dense_score
   FROM cb_embeddings
   WHERE local_only = true
     AND source_account_id = ANY(:allowed_accounts)
     AND topic_id = ANY(:allowed_topics)
   ORDER BY vector <=> :query_vector
   LIMIT :K;
   ```
3. Return top-K=20 (configurable; env var `NCLAW_DENSE_K`, validated range [5, 100]).

### Index type decision

| | IVFFlat (P1) | HNSW (P2+) |
|---|---|---|
| Corpus size | <1M chunks | >1M chunks |
| Lists / M | 100 | m=16, ef_construction=64 |
| Config flag | n/a | `NCLAW_USE_HNSW=true` |
| Schema change | No | No (pgvector ≥0.5.0 supports both) |

Per ADR-005: IVFFlat `lists=100` for P1. HNSW upgrade is a config-flag switch with no schema migration.

---

## 3. Lexical Keyword Search

**Table:** `cb_embeddings`
**Column:** `content_tsv` (tsvector, generated or maintained via trigger)
**Index:** GIN on `content_tsv`

### tsquery generation

Two parallel queries to cover prose and identifiers:
```
english_tsq  = plainto_tsquery('english', :query)   -- prose words, stemming
simple_tsq   = plainto_tsquery('simple',  :query)   -- identifiers, no stemming
combined_tsq = english_tsq || simple_tsq
```

### GIN lookup and scoring

```sql
SELECT id, chunk_text, ingested_at, topic_id, source_account_id,
       ts_rank_cd(content_tsv, :combined_tsq, 1) AS lexical_score
FROM cb_embeddings
WHERE local_only = true
  AND source_account_id = ANY(:allowed_accounts)
  AND topic_id = ANY(:allowed_topics)
  AND content_tsv @@ :combined_tsq
ORDER BY lexical_score DESC
LIMIT :K;
```

`ts_rank_cd` normalization parameter `1` divides rank by 1 + log(document length). This suppresses very long chunks that happen to contain many query tokens.

- Top-K=20 default (configurable `NCLAW_LEXICAL_K`).
- Eval harness measures GIN index hit rate: a GIN miss (seq-scan fallback) is a warning-level event.

---

## 4. RRF Fusion

### Formula

```
rrf_score(doc) = Σ_lane  1 / (k + rank_i(doc))
```

- `k = 60` (ADR-005 canonical; Cormack et al. default for robust rank fusion).
- `rank_i(doc)` is the 1-based position of `doc` in lane `i` results. Docs absent from a lane get `rank_i = K + 1` (one past the last result).
- Per-lane min-max normalization applied before merge (raw scores mapped to [0,1] within each lane).
- Two lanes for nclaw preset: `dense` (i=1) and `lexical` (i=2).

### Output tuple

```
(chunk_id, rrf_score, dense_score, lexical_score, metadata)
```

`metadata` carries: `topic_id`, `source_account_id`, `ingested_at`, `chunk_text`.

### k override

Callers may pass `NCLAW_RRF_K` in query context to override the default.
- Validated range: **[20, 120]** (LEDGER §G — values outside this range are rejected with `SCHEMA_INVALID`).
- Values below 20 or above 120 return a 400 error with `{error: "SCHEMA_INVALID", field: "k", allowed_range: [20, 120]}`.

### Tie-breaking

Equal `rrf_score` → prefer higher recency: `ORDER BY rrf_score DESC, ingested_at DESC`.

---

## 5. Freshness Boost

Applied as a multiplicative factor on `rrf_score` after RRF fusion:

```
boosted_score = rrf_score * (1 + NCLAW_FRESHNESS_WEIGHT * recency_factor(ingested_at))
```

Where:
```
recency_factor(ingested_at) = exp(-λ * days_since_ingest)
days_since_ingest = (NOW() - ingested_at) / interval '1 day'
λ = 0.01 (default; configurable NCLAW_FRESHNESS_LAMBDA)
```

**Defaults:**
- `NCLAW_FRESHNESS_WEIGHT = 0.1`
- `NCLAW_FRESHNESS_LAMBDA = 0.01`

**Overflow note:** `recency_factor` is bounded in [0, 1] since `exp(−x)` ∈ (0, 1] for x ≥ 0. The maximum boost is `1 + NCLAW_FRESHNESS_WEIGHT * 1 = 1.1` when `days_since_ingest = 0`. Scores do not exceed `rrf_score * 1.1`. Setting `NCLAW_FRESHNESS_WEIGHT = 0` disables the boost entirely.

---

## 6. Re-ranking Layer

**Model:** BGE Reranker v2-m3
**Transport:** HTTP POST to TEI sidecar `/rerank` endpoint (port 8092, per PPI port registry)
**Input set:** top-20 chunks after RRF (including freshness boost)

### Invocation spec

```
POST http://127.0.0.1:8092/rerank
Content-Type: application/json

{
  "query": "<user query text>",
  "texts": ["<chunk_text_1>", ..., "<chunk_text_20>"],
  "truncate": true
}
```

Response:
```json
[
  {"index": 3, "score": 0.987},
  {"index": 0, "score": 0.943},
  ...
]
```

Output: re-sorted chunks using the reranker scores.

### Fail-soft bypass

If the TEI sidecar is unavailable (connection refused, timeout >50ms, or non-200 response):
1. Log a WARN entry: `{event: "reranker_bypass", reason: "<error>", fallback: "rrf_order"}`.
2. Return the top-20 RRF results unmodified (preserve `rrf_score DESC, ingested_at DESC` ordering).
3. Do NOT propagate the error to the caller. Availability of the reranker is not a hard dependency per ADR-006 rerank lane spec (no fallback — fail-soft).

### Latency budgets

| Stage | Budget | Measurement |
|---|---|---|
| Reranker HTTP call | ≤50ms P95 | TEI /rerank round-trip |
| Total retrieval pipeline | ≤200ms P95 | From query embed → ranked output |

These are enforced by the golden eval harness (§8).

---

## 7. PolicyEngine Enforcement

Before every outbound AI gateway tool dispatch that uses hybrid retrieval as context:

```rust
let result = policy_engine.evaluate(tool_id, caller_ctx)?;
match result {
    PolicyResult::Allow => { /* forward */ }
    PolicyResult::Deny(reason) => {
        audit_log.write(AuditEntry {
            timestamp, tool_id, caller_id,
            policy_result: "deny",
            policy_reason: reason.clone(),
            latency_ms,
        });
        return Err(PolicyDenied { tool_id, policy_reason: reason });
        // HTTP surface: 403 with body {"tool_id": "...", "policy_reason": "..."}
    }
}
// On Allow — also write audit log
audit_log.write(AuditEntry {
    timestamp, tool_id, caller_id,
    policy_result: "allow",
    policy_reason: None,
    latency_ms,
});
```

**Required audit log fields (per check, always written):**
- `timestamp` — ISO-8601 UTC
- `tool_id` — identifier of the AI gateway tool
- `caller_id` — session or user identifier
- `policy_result` — `"allow"` or `"deny"`
- `latency_ms` — time taken for evaluate() call
- `policy_reason` — populated on Deny; null on Allow

Policy enforcement fires on every outbound tool dispatch — the reranker bypass path does not skip policy. If the reranker is down, policy still fires before the (un-reranked) results are used as context.

---

## 8. Golden Evaluation Harness

### Eval script interface

```
eval_retrieval(fixtures_path: Path, k: int) -> EvalResult
```

```
EvalResult {
    p50_latency_ms: float,
    p95_latency_ms: float,
    recall_at_k: float,    // fraction of golden answers in top-K
    precision_at_k: float, // fraction of top-K results that are golden answers
    gin_hit_rate: float,   // fraction of lexical queries hitting GIN index (not seq-scan)
    fixtures_run: int,
    fixtures_passed: int,
}
```

**Latency targets:** P50 < 100ms, P95 < 200ms (full pipeline, on local Postgres, no reranker in loop for latency measurement — reranker adds up to 50ms on top).

### Golden fixture categories (10+ pairs required)

| # | Category | Query example | Expected behavior |
|---|---|---|---|
| F-01 | Semantic (concept) | "how did I decide to use Tauri for the desktop app?" | Returns cb_embeddings chunks about Tauri decision discussion |
| F-02 | Semantic (concept) | "what are my preferences for morning productivity?" | Returns memory chunks with productivity preference facts |
| F-03 | Lexical (exact identifier) | "hybrid_retrieve function signature" | GIN hit on exact token "hybrid_retrieve"; dense lane may miss |
| F-04 | Lexical (exact identifier) | "NCLAW_RRF_K config parameter" | GIN hit on "NCLAW_RRF_K"; must appear in top-3 |
| F-05 | Mixed (concept + identifier) | "what is content_tsv and how is it indexed?" | Both lanes contribute; RRF fusion improves recall over single-lane |
| F-06 | Mixed (concept + identifier) | "PolicyEngine evaluate before dispatch" | Both exact tokens and semantic meaning retrieval |
| F-07 | Recency-sensitive | "latest decision about embedding model" | Freshness boost surfaces newer chunk over older duplicate with same semantic content |
| F-08 | Recency-sensitive | "most recent API key rotation decision" | Newer chunk wins tie when `rrf_score` is equal |
| F-09 | Privacy-scoped (positive) | Query within allowed `source_account_id` | Returns chunks for that account |
| F-10 | Privacy-scoped (negative) | Query with `source_account_id = 'other'` not in `allowed_accounts` | Returns zero results; no cross-account leak |
| F-11 | GIN miss / seq-scan detection | Rare multi-token identifier not in GIN index | Log warning; dense lane compensates |
| F-12 | Empty result — no matching chunks | Highly specific query with no matching data | Returns empty list; no error; latency still within budget |

All fixtures are stored in `nclaw/core/eval/fixtures/retrieval_fixtures.json` (created in E5/W11 implementation ticket).

---

## 9. Environment Variables

| Variable | Default | Description |
|---|---|---|
| `NCLAW_DENSE_K` | 20 | Top-K for dense lane |
| `NCLAW_LEXICAL_K` | 20 | Top-K for lexical lane |
| `NCLAW_RRF_K` | 60 | RRF k constant; override range [20,120] |
| `NCLAW_FRESHNESS_WEIGHT` | 0.1 | Freshness boost weight |
| `NCLAW_FRESHNESS_LAMBDA` | 0.01 | Recency decay constant λ |
| `TEI_RERANKER_URL` | `http://127.0.0.1:8092` | TEI BGE Reranker v2-m3 endpoint |
| `TEI_EMBEDDER_URL` | `http://127.0.0.1:8080` | TEI BGE-M3 embedder endpoint |
| `NCLAW_RERANKER_TIMEOUT_MS` | 50 | Reranker HTTP call timeout; fail-soft on exceed |

---

## 10. Out of Scope (nclaw preset)

Per ADR-005, the following are explicitly excluded from nClaw's retrieval pipeline:

- **Sparse lane** (BM25/ParadeDB JSONB term-weight vectors) — deferred to ADR-005a / P2. Corpus too small to justify storage cost.
- **ColBERT late-interaction lane** — deferred to ADR-005a / P2. Same rationale.
- **Full `clawde-intelligence` 5-lane stack** — used by ClawDE for large code corpora; nclaw uses the lighter 3-component stack.

The interface boundary (`bm25_query(corpus, query, k) → [(id, score)]`) is defined in E5/W11-T03 to ensure future lane additions are non-breaking.

---

## Implementation Notes

Runtime Rust implementation is in **E5/W11** tickets:
- `P1-E5-W11-S11-T01` — hybrid_retrieve() Rust function
- `P1-E5-W13-S13-T01` — evaluation harness

This document is the design spec that those Build tickets consume.

**SPORT pointer:** `F-NCLAW:hybrid-retrieval` in `.opencode/phases/sport/F-MASTER.md`
**Function registry:** `hybrid_retrieve()` in `REGISTRY-FUNCTIONS.md`
**Related schema:** `nclaw/.github/wiki/architecture/db-schema.md` (cb_embeddings table)
