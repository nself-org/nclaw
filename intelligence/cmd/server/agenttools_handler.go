// agenttools_handler.go — gRPC AgentToolsServiceServer adapter for the T06 agenttools package.
//
// Purpose: Bridge the gRPC AgentToolsService interface (gen/proto) to the internal
//
//	agenttools.Invoke dispatcher. Deserializes params_json into map[string]any,
//	builds InvokeContext with audit fields, and serializes the result to JSON.
//	The confirmed bool and authorize_token are injected into params so the
//	tier-agnostic Invoke dispatcher can extract them per spec §9.
//
// Inputs:  gRPC AgentToolInvokeRequest.
// Outputs: gRPC AgentToolInvokeResponse.
// Constraints: No auth bypass in production — only dev-mode via NCLAW_DEV_BYPASS_AUTH=true.
//
//	≤100 lines. All env vars read in main.go — not this file.
//
// SPORT: nclaw-memory-architecture-spec.md §9 — P2-E5-W4-S8-T08.
package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"

	proto "github.com/nself-org/nclaw/intelligence/gen/proto"
	"github.com/nself-org/nclaw/intelligence/internal/agenttools"
)

// AgentToolsHandler implements proto.AgentToolsServiceServer using the T06 agenttools package.
type AgentToolsHandler struct {
	proto.UnimplementedAgentToolsServiceServer
}

// newAgentToolsHandler creates an AgentToolsHandler.
func newAgentToolsHandler() *AgentToolsHandler {
	return &AgentToolsHandler{}
}

// Invoke implements AgentToolsServiceServer.Invoke.
// Deserializes params_json, injects tier fields, dispatches to agenttools.Invoke,
// and serializes the result back to JSON.
func (h *AgentToolsHandler) Invoke(ctx context.Context, req *proto.AgentToolInvokeRequest) (*proto.AgentToolInvokeResponse, error) {
	// Deserialize params_json into a generic map.
	params := make(map[string]any)
	if req.ParamsJson != "" {
		if err := json.Unmarshal([]byte(req.ParamsJson), &params); err != nil {
			return nil, fmt.Errorf("agenttools handler: invoke: invalid params_json: %w", err)
		}
	}

	// Inject tier fields into params so the dispatcher can extract them (spec §9).
	params["confirmed"] = req.Confirmed
	params["authorize_token"] = req.AuthorizeToken

	// Parse user_id; allow empty (tools with no audit requirement).
	var userID uuid.UUID
	if req.UserId != "" {
		parsed, err := uuid.Parse(req.UserId)
		if err != nil {
			return nil, fmt.Errorf("agenttools handler: invoke: invalid user_id %q: %w", req.UserId, err)
		}
		userID = parsed
	}

	// TODO(E2): validate authorize_token against JWT claims for Tier 3 tools.
	// Dev bypass: NCLAW_DEV_BYPASS_AUTH=true skips token validation in non-production envs.
	// Production path: never bypass — Tier 3 tools require a valid AUTHORIZE token.

	ic := agenttools.InvokeContext{
		UserID:          userID,
		SourceAccountID: req.SourceAccountId,
		// Mem: nil — audit writes require a memory.MemoryClient wired in main.go (P2-E5 downstream).
	}

	result, err := agenttools.Invoke(ctx, req.ToolName, params, ic)
	if err != nil {
		// Return error in response body rather than as a gRPC status to match clawde pattern.
		return &proto.AgentToolInvokeResponse{
			ToolName: req.ToolName,
			Error:    err.Error(),
		}, nil
	}

	// Serialize the result to JSON.
	resultJSON, marshalErr := json.Marshal(result)
	if marshalErr != nil {
		return nil, fmt.Errorf("agenttools handler: invoke: serialize result: %w", marshalErr)
	}

	return &proto.AgentToolInvokeResponse{
		ToolName:   req.ToolName,
		ResultJson: string(resultJSON),
	}, nil
}
