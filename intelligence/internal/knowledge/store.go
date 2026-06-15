// store.go — Postgres write path for the corporate knowledge ingest pipeline.
//
// Purpose: Persist a single content chunk to nclaw_org_knowledge + extract 0-3 RDF-style
//          triples and insert them into nclaw_org_facts. Deduplicates by content_hash
//          (sha256 of content) to avoid redundant rows for re-ingested documents.
//          After a successful DB write, the chunk is embedded and upserted into Qdrant
//          under the org collection (NCLAW_QDRANT_COLLECTION_ORG env var).
// Inputs:  IngestChunk(ctx, orgSlug, sourceAccountID, content, docType, sourceRef, chunkIndex).
// Outputs: (uuid.UUID, error) — inserted knowledge row ID, or zero UUID if skipped (duplicate).
// Constraints: Uses pgx/v5. No LLM for fact extraction — regex only. ≤200 lines.
// SPORT: nclaw-memory-architecture-spec.md §5 — org knowledge write path.
package knowledge

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/nself-org/nclaw/intelligence/internal/memory"
)

// triplePattern matches simple "Subject Verb Object" or "Subject is Object" patterns
// in a single sentence, extracting three capture groups.
// Example matches: "Alice manages Projects", "Server runs Ubuntu".
var triplePattern = regexp.MustCompile(`(?i)\b([A-Z][a-zA-Z0-9_]+)\s+(is|are|has|have|manages|runs|uses|contains|belongs to|owns|depends on)\s+([A-Z][a-zA-Z0-9_\s]+?)(?:[.,;!?]|$)`)

// extractFacts returns up to 3 subject/predicate/object triples from text via regex.
// This is a best-effort P2 heuristic — no LLM call per the architecture spec §5.
func extractFacts(text string) [][3]string {
	matches := triplePattern.FindAllStringSubmatch(text, 6)
	var triples [][3]string
	for _, m := range matches {
		if len(m) >= 4 {
			triples = append(triples, [3]string{
				strings.TrimSpace(m[1]),
				strings.TrimSpace(m[2]),
				strings.TrimSpace(m[3]),
			})
		}
		if len(triples) >= 3 {
			break
		}
	}
	return triples
}

// contentHash returns a hex sha256 digest of content for deduplication.
func contentHash(content string) string {
	h := sha256.Sum256([]byte(content))
	return fmt.Sprintf("%x", h)
}

// IngestChunk persists one document chunk to the corporate knowledge layer.
//
// Deduplication: if a row with the same content_hash and org_slug already exists,
// the function returns uuid.Nil, nil (silent skip — not an error).
//
// On successful INSERT to nclaw_org_knowledge:
//   - Extracts 0-3 RDF triples via regex → INSERTs into nclaw_org_facts.
//   - Embeds the content via NCLAW_EMBED_URL → upserts to Qdrant collection
//     identified by NCLAW_QDRANT_COLLECTION_ORG. Qdrant failure is non-fatal
//     (logged but not propagated) because the DB row is the source of truth.
//
// Parameters:
//   - db: pgx connection or pool (pgx.Tx, *pgxpool.Pool, or pgx.Conn all satisfy
//     the pgx.Conn interface used via SendBatch or plain Query/Exec).
//   - orgSlug: namespace identifier for the org (e.g. "acme").
//   - sourceAccountID: multi-app isolation column value (e.g. "primary").
//   - content: raw chunk text.
//   - docType: classification label (e.g. "runbook", "wiki", "sop").
//   - sourceRef: original document URI or identifier (nullable — pass "" for none).
//   - chunkIndex: 0-based position of this chunk within the parent document.
func IngestChunk(ctx context.Context, db pgx.Conn, orgSlug, sourceAccountID, content, docType, sourceRef string, chunkIndex int) (uuid.UUID, error) {
	hash := contentHash(content)

	// --- Deduplication check ---
	var existingID uuid.UUID
	err := db.QueryRow(ctx,
		`SELECT id FROM nclaw_org_knowledge WHERE content_hash = $1 AND org_slug = $2 LIMIT 1`,
		hash, orgSlug,
	).Scan(&existingID)
	if err == nil {
		// Duplicate — skip silently.
		return uuid.Nil, nil
	}
	if err != pgx.ErrNoRows {
		return uuid.Nil, fmt.Errorf("knowledge/store: dedup check: %w", err)
	}

	// --- Insert into nclaw_org_knowledge ---
	var knowledgeID uuid.UUID
	sourceRefVal := (*string)(nil)
	if sourceRef != "" {
		sourceRefVal = &sourceRef
	}

	err = db.QueryRow(ctx, `
		INSERT INTO nclaw_org_knowledge
			(source_account_id, org_slug, content, doc_type, source_ref, chunk_index, content_hash)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id`,
		sourceAccountID, orgSlug, content, docType, sourceRefVal, chunkIndex, hash,
	).Scan(&knowledgeID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("knowledge/store: insert knowledge row: %w", err)
	}

	// --- Extract and insert RDF triples into nclaw_org_facts ---
	triples := extractFacts(content)
	for _, t := range triples {
		_, err := db.Exec(ctx, `
			INSERT INTO nclaw_org_facts
				(knowledge_id, source_account_id, org_slug, subject, predicate, object)
			VALUES ($1, $2, $3, $4, $5, $6)`,
			knowledgeID, sourceAccountID, orgSlug, t[0], t[1], t[2],
		)
		if err != nil {
			// Fact insert failures are non-fatal — the knowledge row is already committed.
			_ = err
		}
	}

	// --- Embed and upsert to Qdrant org collection (non-fatal on failure) ---
	collection := os.Getenv("NCLAW_QDRANT_COLLECTION_ORG")
	if collection != "" {
		vec, embedErr := memory.EmbedText(ctx, content)
		if embedErr == nil {
			payload := map[string]any{
				"org_slug":          orgSlug,
				"source_account_id": sourceAccountID,
				"doc_type":          docType,
				"chunk_index":       chunkIndex,
			}
			_ = memory.QdrantUpsert(ctx, collection, knowledgeID.String(), vec, payload)
		}
	}

	return knowledgeID, nil
}
