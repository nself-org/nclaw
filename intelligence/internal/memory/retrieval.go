// retrieval.go — BM25 + dense + graph → RRF → rerank search pipeline.
//
// Purpose: Implements Search, the full retrieval pipeline for nclaw personal memory.
//          Three retrieval lanes run in sequence: BM25 sparse (Postgres tsvector),
//          BGE-M3 dense (Qdrant ANN), FalkorDB graph (Cypher, graceful skip).
//          RRF fuses the three ranked lists; bge-reranker-v2-m3 reranks top-20→top-5.
// Inputs:  pgx connection, query string, userID, sourceAccountID, topK.
// Outputs: []MemoryResult ordered by reranked score descending.
// Constraints: Graph path skips (no panic) when NCLAW_FALKORDB_URL unset.
//              All URLs from env (NCLAW_QDRANT_URL, NCLAW_EMBED_URL, NCLAW_FALKORDB_URL,
//              NCLAW_QDRANT_COLLECTION_PERSONAL). ≤250 lines.
// SPORT: nclaw-memory-architecture-spec.md §6.
package memory

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// rerankHTTPClient is a dedicated client for the rerank endpoint.
var rerankHTTPClient = &http.Client{Timeout: 15 * time.Second}

// candidateDoc holds a candidate memory document during the retrieval pipeline.
type candidateDoc struct {
	id      string
	content string
}

// Search executes the full retrieval pipeline: BM25 + dense + graph → RRF → rerank.
//
// Pipeline (per spec §6):
//  1. BM25: SELECT top-20 from nclaw_user_memories WHERE content_tsv @@ plainto_tsquery.
//  2. Dense: embed query → Qdrant search top-20.
//  3. Graph: FalkorDB Cypher query top-20 (skipped when NCLAW_FALKORDB_URL empty).
//  4. RRF fusion (k=60) over three ID rankings → merged candidate set.
//  5. Rerank: POST NCLAW_EMBED_URL/rerank with top-20 docs → bge-reranker-v2-m3 scores.
//  6. Return top topK results as []MemoryResult.
func Search(
	ctx context.Context,
	pool *pgx.Conn,
	query string,
	userID uuid.UUID,
	sourceAccountID string,
	topK int,
) ([]MemoryResult, error) {
	if topK <= 0 {
		topK = 5
	}
	if sourceAccountID == "" {
		sourceAccountID = "primary"
	}

	// Step 1: BM25 sparse retrieval via Postgres tsvector.
	bm25IDs, bm25Docs, err := bm25Search(ctx, pool, query, sourceAccountID, userID, 20)
	if err != nil {
		return nil, fmt.Errorf("retrieval: BM25: %w", err)
	}

	// Step 2: Dense retrieval via BGE-M3 + Qdrant.
	denseIDs, denseDocs, err := denseSearch(ctx, query, 20)
	if err != nil {
		// Non-fatal: dense unavailable → fallback to BM25 only.
		denseIDs = nil
		denseDocs = nil
	}

	// Step 3: Graph retrieval via FalkorDB (graceful skip when URL empty).
	graphIDs, graphDocs, _ := graphSearch(ctx, userID.String(), 20)

	// Step 4: RRF fusion over three ID rankings.
	rankings := [][]string{bm25IDs, denseIDs, graphIDs}
	rrfScores := RRFScore(rankings, 60.0)

	// Merge deduplicated candidate set.
	allDocs := make(map[string]string)
	for id, content := range bm25Docs {
		allDocs[id] = content
	}
	for id, content := range denseDocs {
		if _, ok := allDocs[id]; !ok {
			allDocs[id] = content
		}
	}
	for id, content := range graphDocs {
		if _, ok := allDocs[id]; !ok {
			allDocs[id] = content
		}
	}

	// Sort by RRF score descending, take top 20.
	type scored struct {
		id      string
		content string
		score   float64
	}
	candidates := make([]scored, 0, len(rrfScores))
	for id, score := range rrfScores {
		candidates = append(candidates, scored{id: id, content: allDocs[id], score: score})
	}
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].score > candidates[j].score
	})
	if len(candidates) > 20 {
		candidates = candidates[:20]
	}

	// Step 5: Rerank top-20 via bge-reranker-v2-m3.
	docs := make([]candidateDoc, len(candidates))
	for i, c := range candidates {
		docs[i] = candidateDoc{id: c.id, content: c.content}
	}
	reranked, err := rerank(ctx, query, docs)
	if err != nil {
		// Non-fatal: skip rerank → keep RRF order.
		reranked = docs
	}

	// Step 6: Build final MemoryResult slice.
	results := make([]MemoryResult, 0, topK)
	for i, doc := range reranked {
		if i >= topK {
			break
		}
		id, _ := uuid.Parse(doc.id)
		results = append(results, MemoryResult{
			ID:      id,
			Content: doc.content,
			Score:   rrfScores[doc.id],
		})
	}
	return results, nil
}

// bm25Search executes a Postgres BM25 query using tsvector + plainto_tsquery.
// Returns ordered ID list and id→content map for up to limit rows.
func bm25Search(ctx context.Context, pool *pgx.Conn, query string, sourceAccountID string, userID uuid.UUID, limit int) ([]string, map[string]string, error) {
	rows, err := pool.Query(ctx, `
		SELECT id::text, content
		FROM nclaw_user_memories
		WHERE content_tsv @@ plainto_tsquery('english', $1)
		  AND source_account_id = $2
		  AND user_id = $3
		  AND valid_until IS NULL
		ORDER BY ts_rank(content_tsv, plainto_tsquery('english', $1)) DESC
		LIMIT $4
	`, query, sourceAccountID, userID, limit)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	ids := make([]string, 0, limit)
	docs := make(map[string]string)
	for rows.Next() {
		var id, content string
		if err := rows.Scan(&id, &content); err != nil {
			continue
		}
		ids = append(ids, id)
		docs[id] = content
	}
	return ids, docs, nil
}

// denseSearch embeds the query and searches Qdrant for top-K nearest vectors.
// Returns ordered ID list and id→content map extracted from Qdrant payloads.
func denseSearch(ctx context.Context, query string, topK int) ([]string, map[string]string, error) {
	vec, err := EmbedText(ctx, query)
	if err != nil {
		return nil, nil, fmt.Errorf("dense: embed: %w", err)
	}

	collection := os.Getenv("NCLAW_QDRANT_COLLECTION_PERSONAL")
	if collection == "" {
		collection = "nclaw_personal"
	}

	matches, err := QdrantSearch(ctx, collection, vec, topK, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("dense: qdrant: %w", err)
	}

	ids := make([]string, 0, len(matches))
	docs := make(map[string]string)
	for _, m := range matches {
		ids = append(ids, m.ID)
		if content, ok := m.Payload["content"].(string); ok {
			docs[m.ID] = content
		}
	}
	return ids, docs, nil
}

// graphSearch retrieves current facts from FalkorDB for graph-based candidates.
// Gracefully returns empty slices when NCLAW_FALKORDB_URL is unset.
func graphSearch(ctx context.Context, userID string, limit int) ([]string, map[string]string, error) {
	facts, err := GraphQuery(ctx, userID, limit)
	if err != nil || len(facts) == 0 {
		return nil, nil, nil
	}
	ids := make([]string, 0, len(facts))
	docs := make(map[string]string)
	for _, f := range facts {
		ids = append(ids, f.FactID)
		docs[f.FactID] = fmt.Sprintf("%s %s %s", f.Subject, f.Predicate, f.Object)
	}
	return ids, docs, nil
}

// rerank calls the bge-reranker-v2-m3 cross-encoder at NCLAW_EMBED_URL/rerank.
// POST /rerank {"query": "...", "documents": ["...", ...]} → {"scores": [float64]}
// Returns candidates sorted by rerank score descending.
func rerank(ctx context.Context, query string, docs []candidateDoc) ([]candidateDoc, error) {
	base := os.Getenv("NCLAW_EMBED_URL")
	if base == "" {
		return docs, nil
	}

	texts := make([]string, len(docs))
	for i, d := range docs {
		texts[i] = d.content
	}

	body := map[string]any{"query": query, "documents": texts}
	data, err := json.Marshal(body)
	if err != nil {
		return docs, fmt.Errorf("rerank: marshal: %w", err)
	}

	endpoint := strings.TrimRight(base, "/") + "/rerank"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return docs, fmt.Errorf("rerank: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := rerankHTTPClient.Do(req)
	if err != nil {
		return docs, fmt.Errorf("rerank: request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return docs, fmt.Errorf("rerank: HTTP %d: %s", resp.StatusCode, b)
	}

	var result struct {
		Scores []float64 `json:"scores"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil || len(result.Scores) != len(docs) {
		return docs, nil
	}

	type scored struct {
		doc   candidateDoc
		score float64
	}
	ranked := make([]scored, len(docs))
	for i, d := range docs {
		ranked[i] = scored{doc: d, score: result.Scores[i]}
	}
	sort.Slice(ranked, func(i, j int) bool {
		return ranked[i].score > ranked[j].score
	})

	out := make([]candidateDoc, len(ranked))
	for i, r := range ranked {
		out[i] = r.doc
	}
	return out, nil
}

