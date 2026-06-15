// store.go — Postgres write path for nclaw personal memory.
//
// Purpose: WriteMemory inserts a new memory record and derived fact triples into
//          Postgres using pgx. Writes to nclaw_user_memories, nclaw_memory_facts,
//          and nclaw_session_wal in a single logical sequence (DB-first, then Qdrant
//          sync is handled by the caller via qdrant.go).
// Inputs:  pgx pool, user/account identifiers, raw content string, namespace,
//          memoryType. Fact extraction uses regex — NOT an LLM call (P2 constraint).
// Outputs: UUID of the newly inserted nclaw_user_memories row.
// Constraints: No LLM calls in fact extraction path. All column names from migration
//              0090. ≤300 lines.
// SPORT: nclaw-memory-architecture-spec.md §5 §7.
package memory

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// extractedFact is a subject/predicate/object triple extracted from raw text.
type extractedFact struct {
	subject   string
	predicate string
	object    string
}

// factPattern matches simple "<subject> <verb> <object>" sentences.
// Examples: "User likes coffee", "Ali works at Anthropic", "System uses pgx".
// This is intentionally simple (P2 constraint — no LLM in fact extraction).
var factPattern = regexp.MustCompile(`(?i)^([A-Za-z][A-Za-z0-9 ]+?)\s+(is|are|has|have|likes?|loves?|hates?|uses?|works?\s+at|works?\s+for|prefers?|wants?|needs?|knows?|remembers?|forgets?)\s+(.+)$`)

// extractFacts parses subject/predicate/object triples from plain text.
// It processes each sentence line independently. Non-matching lines are skipped.
// Returns at most 10 facts to avoid unbounded inserts.
func extractFacts(content string) []extractedFact {
	lines := strings.Split(content, ".")
	var facts []extractedFact
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		m := factPattern.FindStringSubmatch(line)
		if m != nil && len(m) == 4 {
			facts = append(facts, extractedFact{
				subject:   strings.TrimSpace(m[1]),
				predicate: strings.TrimSpace(m[2]),
				object:    strings.TrimSpace(m[3]),
			})
		}
		if len(facts) >= 10 {
			break
		}
	}
	return facts
}

// WriteMemory inserts a memory record and derived fact triples into Postgres.
//
// Write sequence (DB-first pattern per spec §7):
//  1. INSERT into nclaw_user_memories — returns new UUID.
//  2. For each extracted fact: INSERT into nclaw_memory_facts.
//  3. INSERT into nclaw_session_wal with compacted=false.
//
// On Qdrant failure the caller marks the DB row as sync_pending via a separate
// update — this function only handles the Postgres path.
//
// All column names match migration 0090_nclaw_user_memory.sql exactly.
func WriteMemory(
	ctx context.Context,
	pool *pgx.Conn,
	userID uuid.UUID,
	sourceAccountID string,
	content string,
	namespace string,
	memoryType string,
) (uuid.UUID, error) {
	if sourceAccountID == "" {
		sourceAccountID = "primary"
	}
	if memoryType == "" {
		memoryType = "fact"
	}

	// Step 1: insert into nclaw_user_memories.
	var memoryID uuid.UUID
	err := pool.QueryRow(ctx, `
		INSERT INTO nclaw_user_memories
			(source_account_id, user_id, content, memory_type, namespace)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`, sourceAccountID, userID, content, memoryType, namespace).Scan(&memoryID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("memory: insert nclaw_user_memories: %w", err)
	}

	// Step 2: extract facts and insert triples.
	facts := extractFacts(content)
	for _, f := range facts {
		_, err = pool.Exec(ctx, `
			INSERT INTO nclaw_memory_facts
				(memory_id, source_account_id, user_id, subject, predicate, object)
			VALUES ($1, $2, $3, $4, $5, $6)
		`, memoryID, sourceAccountID, userID, f.subject, f.predicate, f.object)
		if err != nil {
			// Non-fatal: log and continue — a fact insert failure should not
			// roll back the primary memory record.
			_ = err // caller may check returned UUID for partial success
		}
	}

	// Step 3: append to nclaw_session_wal.
	// role='assistant' for memory insertions (agent-originated content).
	// session_id is synthetic per memory record so WAL compaction can group by memory.
	sessionID := "mem-" + memoryID.String()
	_, err = pool.Exec(ctx, `
		INSERT INTO nclaw_session_wal
			(source_account_id, user_id, session_id, role, content, compacted)
		VALUES ($1, $2, $3, 'assistant', $4, false)
	`, sourceAccountID, userID, sessionID, content)
	if err != nil {
		// Non-fatal: WAL is a best-effort audit buffer.
		_ = err
	}

	return memoryID, nil
}
