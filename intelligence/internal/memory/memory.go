// memory.go — Public memory RPC functions: MemorySearch, MemoryInsert, MemoryReplace.
//
// Purpose: Expose the three LLM-callable memory tool functions defined in spec §7.
//          These are explicit agent tool calls — the LLM invokes them, they are NOT
//          passive background retrieval. Each function wires the store + retrieval
//          sub-packages. MemoryReplace preserves temporal history by setting
//          valid_until on the old fact rather than deleting it.
// Inputs:  pgx.Conn pool, user/account identifiers, content/namespace strings.
// Outputs: []MemoryResult (search) or UUID (insert/replace) + error.
// Constraints: Signatures match spec §7 exactly. No LLM calls in this package.
//              All env vars via os.Getenv. ≤150 lines.
// SPORT: nclaw-memory-architecture-spec.md §7.
package memory

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// MemoryResult is a single retrieved memory record with its RRF-reranked score.
type MemoryResult struct {
	// ID is the nclaw_user_memories primary key.
	ID uuid.UUID
	// Content is the raw text of the memory.
	Content string
	// MemoryType is the memory classification: "fact" | "preference" | "decision" | "audit".
	MemoryType string
	// Namespace is the scoped namespace: e.g. "personal/nclaw_{userID}".
	Namespace string
	// ValidFrom is when this memory was first stored.
	ValidFrom time.Time
	// ValidUntil is the expiry time — nil means the record is currently active.
	ValidUntil *time.Time
	// Score is the RRF-reranked relevance score (higher = more relevant).
	Score float64
}

// MemorySearch retrieves relevant memory facts for a user query.
//
// Executes the full retrieval pipeline: BM25 + BGE-M3 dense + FalkorDB graph
// → RRF fusion (k=60) → bge-reranker-v2-m3 cross-encoder rerank top-20 → top-K.
//
// namespace: "personal/nclaw_{userID}" or "system/nclaw" (used for Qdrant payload filter in future).
// topK: number of results to return (default 5 if ≤0).
func MemorySearch(ctx context.Context, db *pgx.Conn, query string, userID uuid.UUID, sourceAccountID string, topK int) ([]MemoryResult, error) {
	if topK <= 0 {
		topK = 5
	}
	return Search(ctx, db, query, userID, sourceAccountID, topK)
}

// MemoryInsert stores a new memory fact for a user.
//
// Write sequence: INSERT into nclaw_user_memories → extract SPO facts → INSERT
// into nclaw_memory_facts → INSERT into nclaw_session_wal → attempt Qdrant upsert
// (on Qdrant failure, the DB row remains valid — sync_pending handling is out of scope
// for P2 and is covered by the nightly WAL compaction job).
//
// memoryType: "fact" | "preference" | "decision" | "audit". Defaults to "fact".
// Returns the UUID of the newly inserted nclaw_user_memories row.
func MemoryInsert(ctx context.Context, db *pgx.Conn, userID uuid.UUID, sourceAccountID string, content string, namespace string, memoryType string) (uuid.UUID, error) {
	id, err := WriteMemory(ctx, db, userID, sourceAccountID, content, namespace, memoryType)
	if err != nil {
		return uuid.Nil, fmt.Errorf("memory: insert: %w", err)
	}

	// Async Qdrant upsert — best-effort. Failures are non-fatal; WAL compaction
	// will re-sync on the next scheduled run.
	go func() {
		bgCtx := context.Background()
		vec, embedErr := EmbedText(bgCtx, content)
		if embedErr != nil {
			return
		}
		collection := ""
		if collection == "" {
			collection = "nclaw_personal"
		}
		payload := map[string]any{
			"user_id":           userID.String(),
			"source_account_id": sourceAccountID,
			"namespace":         namespace,
			"content":           content,
			"memory_type":       memoryType,
		}
		_ = QdrantUpsert(bgCtx, collection, id.String(), vec, payload)
	}()

	return id, nil
}

// MemoryReplace marks the old fact as expired and inserts the new fact.
//
// This preserves temporal history — old facts are NEVER deleted.
// The old nclaw_memory_facts row has its valid_until set to now().
// A new nclaw_user_memories + nclaw_memory_facts row is created with the new content.
//
// oldFactID: the nclaw_memory_facts.id of the fact to replace.
// Returns the UUID of the newly inserted nclaw_user_memories row.
func MemoryReplace(ctx context.Context, db *pgx.Conn, userID uuid.UUID, sourceAccountID string, oldFactID uuid.UUID, newContent string, namespace string) (uuid.UUID, error) {
	// Step 1: expire the old fact record (temporal preservation — not delete).
	_, err := db.Exec(ctx, `
		UPDATE nclaw_memory_facts
		SET valid_until = now()
		WHERE id = $1
		  AND user_id = $2
		  AND source_account_id = $3
		  AND valid_until IS NULL
	`, oldFactID, userID, sourceAccountID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("memory: replace: expire old fact %s: %w", oldFactID, err)
	}

	// Step 2: insert the replacement memory.
	newID, err := MemoryInsert(ctx, db, userID, sourceAccountID, newContent, namespace, "fact")
	if err != nil {
		return uuid.Nil, fmt.Errorf("memory: replace: insert new: %w", err)
	}

	return newID, nil
}
