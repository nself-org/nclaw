// Purpose: Writes structured audit records for all Tier 2+ tool operations to the
//          nclaw_user_memories table via the MemoryClient interface.
//          Audit records are written BEFORE tool execution so failed ops are still logged.
// Inputs:  Context, MemoryClient, user ID, sourceAccountID, tool name, params, outcome.
// Outputs: error if the audit write fails (non-fatal — callers may log and continue).
// Constraints: Namespace must be "system/nclaw"; memoryType must be "audit".
//              MemoryClient is an interface so this package is testable without real Postgres.
// SPORT:   §9 — audit pattern for Tier 2+ tools (P2-E5-W3-S6-T06).
package agenttools

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
)

const (
	auditNamespace   = "system/nclaw"
	auditMemoryType  = "audit"
)

// MemoryClient is the interface required to write audit records.
// Satisfied by the memory package from T04 (memory.MemoryInsert).
// Using an interface here keeps agenttools testable without a real Postgres connection.
type MemoryClient interface {
	// MemoryInsert writes a single memory fact to the memory store.
	// Parameters match memory.MemoryInsert from T04.
	MemoryInsert(ctx context.Context, userID uuid.UUID, sourceAccountID string,
		namespace string, memoryType string, fact string) error
}

// auditPayload is the structured JSON fact stored in the audit record.
type auditPayload struct {
	Tool     string         `json:"tool"`
	Params   map[string]any `json:"params,omitempty"`
	Outcome  string         `json:"outcome"`
	UserID   string         `json:"user_id"`
	TakenAt  string         `json:"taken_at"`
}

// WriteAuditRecord writes a Tier 2/3 audit record to nclaw_user_memories via MemoryClient.
// Must be called BEFORE the tool's HTTP execution so that failed ops are still audited.
// If mem is nil, WriteAuditRecord is a no-op (permits use without T04 wired up).
func WriteAuditRecord(
	ctx context.Context,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
	toolName string,
	params map[string]any,
	outcome string,
) error {
	if mem == nil {
		return nil
	}

	payload := auditPayload{
		Tool:    toolName,
		Params:  params,
		Outcome: outcome,
		UserID:  userID.String(),
		TakenAt: time.Now().UTC().Format(time.RFC3339),
	}

	fact, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("agenttools/audit: marshal payload: %w", err)
	}

	if err := mem.MemoryInsert(ctx, userID, sourceAccountID, auditNamespace, auditMemoryType, string(fact)); err != nil {
		return fmt.Errorf("agenttools/audit: write audit record for %q: %w", toolName, err)
	}
	return nil
}
