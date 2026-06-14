// knowledge.go — Public API for the corporate knowledge ingest and query layer.
//
// Purpose: Expose KnowledgeIngest and KnowledgeQuery as the two surface-area entry
//          points for the org knowledge system. KnowledgeIngest chunks the raw document
//          using ChunkDocument (512 tokens / 200 overlap) then calls IngestChunk for
//          each chunk. KnowledgeQuery delegates to QueryKnowledge (RRF pipeline).
//          This file contains only the public wrappers — implementation detail lives in
//          chunker.go, store.go, and query.go.
// Inputs:  KnowledgeIngest(ctx, db, orgSlug, sourceAccountID, docType, sourceRef, rawText).
//          KnowledgeQuery(ctx, db, query, orgSlug, sourceAccountID, topK).
// Outputs: (chunksIngested int, error) and ([]KnowledgeResult, error) respectively.
// Constraints: ≤80 lines. No direct SQL. No direct Qdrant calls. Env: none (delegated).
// SPORT: nclaw-memory-architecture-spec.md §3 §5 — corporate knowledge layer public API.
package knowledge

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// KnowledgeIngest ingests a raw text document into the org knowledge layer.
//
// Steps:
//  1. ChunkDocument(rawText, 512, 200) → ordered chunk list.
//  2. For each chunk: IngestChunk writes to nclaw_org_knowledge + nclaw_org_facts + Qdrant.
//     Duplicate chunks (same content_hash + org_slug) are silently skipped.
//  3. Returns the count of newly inserted chunks (duplicates do not count).
//
// Parameters:
//   - db: pgx connection or pool (passed through to IngestChunk).
//   - orgSlug: org namespace (e.g. "acme").
//   - sourceAccountID: multi-app isolation value (e.g. "primary").
//   - docType: document classification (e.g. "runbook", "wiki", "sop").
//   - sourceRef: original document URI or key (pass "" if unavailable).
//   - rawText: full document text — chunking is handled internally.
func KnowledgeIngest(ctx context.Context, db pgx.Conn, orgSlug, sourceAccountID, docType, sourceRef, rawText string) (int, error) {
	chunks := ChunkDocument(rawText, 512, 200)
	if len(chunks) == 0 {
		return 0, nil
	}

	ingested := 0
	var firstErr error
	for i, chunk := range chunks {
		id, err := IngestChunk(ctx, db, orgSlug, sourceAccountID, chunk, docType, sourceRef, i)
		if err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("knowledge: chunk %d: %w", i, err)
			}
			continue
		}
		// uuid.Nil means the chunk was a duplicate — do not count it.
		if id.String() != "00000000-0000-0000-0000-000000000000" {
			ingested++
		}
	}
	return ingested, firstErr
}

// KnowledgeQuery executes an RRF retrieval query scoped to the given org.
//
// Delegates to QueryKnowledge (BM25 + dense + graph → RRF fusion → top topK).
// Returns an empty slice (not an error) when no results are found.
//
// Parameters:
//   - db: pgx connection or pool.
//   - query: natural language query string.
//   - orgSlug: org namespace — results are strictly isolated to this slug.
//   - sourceAccountID: multi-app isolation value.
//   - topK: maximum number of results to return (clamped to 1 if ≤0).
func KnowledgeQuery(ctx context.Context, db pgx.Conn, query, orgSlug, sourceAccountID string, topK int) ([]KnowledgeResult, error) {
	return QueryKnowledge(ctx, db, query, orgSlug, sourceAccountID, topK)
}
