// Purpose: ToolRegistry and Invoke dispatcher for all 15 nSelf backend agent tools.
//          Maps tool names to handlers and dispatches calls with the correct tier logic.
//          Tier 1: read-only, no extra params. Tier 2: confirmed bool. Tier 3: AUTHORIZE token.
// Inputs:  toolName string, params map[string]any (may include "confirmed", "authorize_token",
//          "user_id" UUID, "source_account_id" string for audit context).
// Outputs: (any, error) — decoded API response or rejection error.
// Constraints: ToolRegistry must have exactly 15 registered entries.
//              No hardcoded IPs — all HTTP goes via NCLAW_NSELF_API_URL.
// SPORT:   §9 full tool surface (P2-E5-W3-S6-T06).
package agenttools

import (
	"context"
	"fmt"

	"github.com/google/uuid"
)

// ToolHandler is the unified function signature for all 15 tools in the registry.
// It accepts the full params map and an InvokeContext carrying audit state.
// The handler extracts its own tier-specific fields (confirmed, authorize_token)
// from params so the Invoke dispatcher remains tier-agnostic.
type ToolHandler func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error)

// InvokeContext carries the audit fields passed to every tool invocation.
// Tier 1 tools ignore these; Tier 2/3 tools use them for WriteAuditRecord.
type InvokeContext struct {
	// Mem is the MemoryClient for audit record writes. May be nil (audit is no-op).
	Mem MemoryClient
	// UserID is the UUID of the user invoking the tool (for audit trail).
	UserID uuid.UUID
	// SourceAccountID is the nSelf source_account_id for audit records.
	SourceAccountID string
}

// ToolRegistry maps tool name → ToolHandler for all 15 agenttools.
// Initialized in init() below. Callers use Invoke() rather than this map directly.
var ToolRegistry = map[string]ToolHandler{}

func init() {
	// Tier 1 — 5 read-only tools (no confirmation, no AUTHORIZE token).
	ToolRegistry["NselfDbQuery"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfDbQuery(ctx, params)
	}
	ToolRegistry["NselfApiGet"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfApiGet(ctx, params)
	}
	ToolRegistry["NselfLogTail"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfLogTail(ctx, params)
	}
	ToolRegistry["NselfMetricsGet"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfMetricsGet(ctx, params)
	}
	ToolRegistry["NselfUserLookup"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfUserLookup(ctx, params)
	}

	// Tier 2 — 6 write tools (require confirmed=true in params).
	ToolRegistry["NselfApiPost"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfApiPost(ctx, params, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfUserUpdate"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfUserUpdate(ctx, params, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfFeatureFlag"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfFeatureFlag(ctx, params, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfNotificationSend"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfNotificationSend(ctx, params, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfPluginEnable"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfPluginEnable(ctx, params, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfPluginDisable"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		return NselfPluginDisable(ctx, params, ic.Mem, ic.UserID, ic.SourceAccountID)
	}

	// Tier 3 — 4 destructive tools (require AUTHORIZE token in params["authorize_token"]).
	ToolRegistry["NselfMigrationRun"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		tok, _ := params["authorize_token"].(string)
		return NselfMigrationRun(ctx, params, tok, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfDeploy"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		tok, _ := params["authorize_token"].(string)
		return NselfDeploy(ctx, params, tok, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfUserDelete"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		tok, _ := params["authorize_token"].(string)
		return NselfUserDelete(ctx, params, tok, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
	ToolRegistry["NselfConfigSet"] = func(ctx context.Context, params map[string]any, ic InvokeContext) (any, error) {
		tok, _ := params["authorize_token"].(string)
		return NselfConfigSet(ctx, params, tok, ic.Mem, ic.UserID, ic.SourceAccountID)
	}
}

// Invoke dispatches a tool call by name. Returns an error if the tool name is unknown.
// params may include:
//   - "confirmed" (bool)  — required by Tier 2 tools
//   - "authorize_token" (string) — required by Tier 3 tools
//
// ic carries optional audit context (Mem, UserID, SourceAccountID).
func Invoke(ctx context.Context, toolName string, params map[string]any, ic InvokeContext) (any, error) {
	handler, ok := ToolRegistry[toolName]
	if !ok {
		return nil, fmt.Errorf("agenttools: unknown tool %q", toolName)
	}
	return handler(ctx, params, ic)
}
