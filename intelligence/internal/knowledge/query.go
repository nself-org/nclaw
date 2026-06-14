// query.go — RRF retrieval pipeline scoped to an org_slug for corporate knowledge.
//
// Purpose: Execute the same three-path RRF pipeline as the personal memory layer
//          (BM25 + dense + graph) but constrained to a single org_slug namespace.
//          Reuses memory.RRFScore and memory.QdrantSearch — does NOT duplicate them.
//          BM25: WHERE org_slug=$1 AND source_account_id=$2 to prevent cross-org leakage.
//          Qdrant: filter payload.org_slug = orgSlug.
//          Graph (FalkorDB): MATCH (n {org_slug: $orgSlug}) ... LIMIT 20; skips if env unset.
// Inputs:  QueryKnowledge(ctx, query, orgSlug, sourceAccountID, topK).
// Outputs: []KnowledgeResult — fused ranked results, at most topK entries.
// Constraints: Imports memory.RRFScore + memory.QdrantSearch (no copy). ≤200 lines.
// SPORT: nclaw-memory-architecture-spec.md §6 — org-scoped retrieval pipeline.
package knowledge

import (
	"context"
	"fmt"
	"net"
	"os"
	"sort"

	"github.com/jackc/pgx/v5"
	"github.com/nself-org/nclaw/intelligence/internal/memory"
)

// KnowledgeResult is a single retrieved document chunk from the org knowledge layer.
type KnowledgeResult struct {
	// ID is the nclaw_org_knowledge UUID.
	ID string
	// Content is the raw chunk text.
	Content string
	// Score is the fused RRF score (higher is more relevant).
	Score float64
	// DocType classifies the source document (e.g. "runbook", "wiki").
	DocType string
	// SourceRef is the original document URI or identifier (may be empty).
	SourceRef string
}

// bm25CandidatesOrg returns up to 20 document IDs from BM25 full-text search
// strictly scoped to (org_slug, source_account_id) to prevent cross-org leakage.
func bm25CandidatesOrg(ctx context.Context, db pgx.Conn, query, orgSlug, sourceAccountID string) ([]string, map[string]KnowledgeResult, error) {
	rows, err := db.Query(ctx, `
		SELECT id, content, doc_type, COALESCE(source_ref, '')
		FROM nclaw_org_knowledge
		WHERE content_tsv @@ plainto_tsquery('english', $1)
		  AND org_slug          = $2
		  AND source_account_id = $3
		  AND (valid_until IS NULL OR valid_until > now())
		ORDER BY ts_rank(content_tsv, plainto_tsquery('english', $1)) DESC
		LIMIT 20`,
		query, orgSlug, sourceAccountID,
	)
	if err != nil {
		return nil, nil, fmt.Errorf("knowledge/query: BM25 query: %w", err)
	}
	defer rows.Close()

	var ids []string
	meta := map[string]KnowledgeResult{}
	for rows.Next() {
		var r KnowledgeResult
		if err := rows.Scan(&r.ID, &r.Content, &r.DocType, &r.SourceRef); err != nil {
			continue
		}
		ids = append(ids, r.ID)
		meta[r.ID] = r
	}
	return ids, meta, rows.Err()
}

// denseCandidatesOrg embeds the query and searches Qdrant filtered by org_slug.
// Returns an empty list (not an error) when NCLAW_QDRANT_COLLECTION_ORG is unset.
func denseCandidatesOrg(ctx context.Context, query, orgSlug string) ([]string, error) {
	collection := os.Getenv("NCLAW_QDRANT_COLLECTION_ORG")
	if collection == "" {
		return nil, nil
	}

	vec, err := memory.EmbedText(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("knowledge/query: embed query: %w", err)
	}

	// Qdrant filter: must match payload field org_slug.
	filter := map[string]any{
		"must": []map[string]any{
			{
				"key":   "org_slug",
				"match": map[string]any{"value": orgSlug},
			},
		},
	}

	matches, err := memory.QdrantSearch(ctx, collection, vec, 20, filter)
	if err != nil {
		return nil, fmt.Errorf("knowledge/query: Qdrant search: %w", err)
	}

	ids := make([]string, 0, len(matches))
	for _, m := range matches {
		ids = append(ids, m.ID)
	}
	return ids, nil
}

// graphCandidatesOrg queries FalkorDB for org-scoped knowledge graph neighbours.
// Returns an empty list (not an error) when NCLAW_FALKORDB_URL is unset or unreachable.
func graphCandidatesOrg(ctx context.Context, orgSlug string) []string {
	addr := os.Getenv("NCLAW_FALKORDB_URL")
	if addr == "" {
		return nil
	}

	// Minimal RESP2 command to FalkorDB via raw TCP.
	// GRAPH.QUERY nclaw_org "MATCH (n {org_slug: 'acme'}) RETURN n.id LIMIT 20"
	graphName := "nclaw_org"
	cypher := fmt.Sprintf("MATCH (n {org_slug: '%s'}) RETURN n.id LIMIT 20", orgSlug)
	cmd := fmt.Sprintf("*3\r\n$11\r\nGRAPH.QUERY\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n",
		len(graphName), graphName, len(cypher), cypher)

	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil
	}
	defer conn.Close()

	if _, err := fmt.Fprint(conn, cmd); err != nil {
		return nil
	}

	// Read up to 4 KB of RESP response; parse id values from result rows.
	buf := make([]byte, 4096)
	n, _ := conn.Read(buf)
	raw := string(buf[:n])

	// Extract UUID-like tokens from the RESP response.
	var ids []string
	for _, tok := range splitRESP(raw) {
		if isUUIDLike(tok) {
			ids = append(ids, tok)
			if len(ids) >= 20 {
				break
			}
		}
	}
	return ids
}

// splitRESP splits a raw RESP response into string tokens (bulk strings, simple strings).
func splitRESP(raw string) []string {
	var tokens []string
	for _, line := range splitLines(raw) {
		if len(line) > 1 && (line[0] == '+' || line[0] == '$') {
			tokens = append(tokens, line[1:])
		} else if len(line) > 0 && line[0] != '*' && line[0] != ':' && line[0] != '-' {
			tokens = append(tokens, line)
		}
	}
	return tokens
}

func splitLines(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			line := s[start:i]
			if len(line) > 0 && line[len(line)-1] == '\r' {
				line = line[:len(line)-1]
			}
			out = append(out, line)
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}

// isUUIDLike returns true for strings that look like UUIDs (36 chars with hyphens).
func isUUIDLike(s string) bool {
	if len(s) != 36 {
		return false
	}
	return s[8] == '-' && s[13] == '-' && s[18] == '-' && s[23] == '-'
}

// QueryKnowledge executes the RRF retrieval pipeline scoped to orgSlug.
//
// Pipeline:
//  1. BM25: full-text search in nclaw_org_knowledge filtered by org_slug + source_account_id.
//  2. Dense: embed query → Qdrant ANN search filtered by payload.org_slug.
//  3. Graph: FalkorDB Cypher scoped to org_slug (skips if env unset).
//  4. RRF fusion (k=60) over three ranked lists.
//  5. Sort by fused score desc, return top topK.
//
// Results include only content visible in the BM25 meta map; dense/graph IDs without
// BM25 meta are included in RRF scoring but returned without content (Score only).
func QueryKnowledge(ctx context.Context, db pgx.Conn, query, orgSlug, sourceAccountID string, topK int) ([]KnowledgeResult, error) {
	if topK <= 0 {
		topK = 5
	}

	bm25IDs, meta, err := bm25CandidatesOrg(ctx, db, query, orgSlug, sourceAccountID)
	if err != nil {
		return nil, err
	}

	denseIDs, err := denseCandidatesOrg(ctx, query, orgSlug)
	if err != nil {
		// Dense failure is non-fatal — degrade to BM25 + graph only.
		denseIDs = nil
	}

	graphIDs := graphCandidatesOrg(ctx, orgSlug)

	// RRF fusion.
	rankings := [][]string{bm25IDs, denseIDs, graphIDs}
	scores := memory.RRFScore(rankings, 60.0)

	// Build result list.
	type scored struct {
		id    string
		score float64
	}
	var ranked []scored
	for id, s := range scores {
		ranked = append(ranked, scored{id, s})
	}
	sort.Slice(ranked, func(i, j int) bool { return ranked[i].score > ranked[j].score })

	results := make([]KnowledgeResult, 0, topK)
	for _, s := range ranked {
		if len(results) >= topK {
			break
		}
		r := meta[s.id]
		r.ID = s.id
		r.Score = s.score
		results = append(results, r)
	}
	return results, nil
}
