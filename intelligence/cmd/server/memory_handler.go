// memory_handler.go — gRPC MemoryServiceServer adapter for the T04 memory package.
//
// Purpose: Bridge the gRPC MemoryService interface (gen/proto) to the internal
//
//	memory package functions (internal/memory). Converts proto request/response
//	types to package types and back. Forwards source_account_id from every
//	request — never defaults it — to preserve multi-app isolation.
//
// Inputs:  gRPC MemorySearchRequest / MemoryInsertRequest / MemoryReplaceRequest.
// Outputs: gRPC MemorySearchResponse / MemoryInsertResponse / MemoryReplaceResponse.
// Constraints: No auth logic here (dev bypass via NCLAW_DEV_BYPASS_AUTH=true; E2 gate).
//
//	≤150 lines. All env vars via os.Getenv in main.go — not this file.
//
// SPORT: nclaw-memory-architecture-spec.md §7 §9 — P2-E5-W4-S8-T08.
package main

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	proto "github.com/nself-org/nclaw/intelligence/gen/proto"
	"github.com/nself-org/nclaw/intelligence/internal/memory"
)

// MemoryHandler implements proto.MemoryServiceServer using the T04 memory package.
type MemoryHandler struct {
	proto.UnimplementedMemoryServiceServer
	// db is the Postgres connection shared across all requests.
	db *pgx.Conn
}

// newMemoryHandler creates a MemoryHandler wrapping the given Postgres connection.
func newMemoryHandler(db *pgx.Conn) *MemoryHandler {
	return &MemoryHandler{db: db}
}

// Search implements MemoryServiceServer.Search.
// Forwards all fields from the request to memory.MemorySearch; never discards source_account_id.
func (h *MemoryHandler) Search(ctx context.Context, req *proto.MemorySearchRequest) (*proto.MemorySearchResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, fmt.Errorf("memory handler: search: invalid user_id %q: %w", req.UserId, err)
	}

	results, err := memory.MemorySearch(ctx, h.db, req.Query, userID, req.SourceAccountId, int(req.TopK))
	if err != nil {
		return nil, fmt.Errorf("memory handler: search: %w", err)
	}

	protoResults := make([]*proto.MemoryResult, 0, len(results))
	for _, r := range results {
		pr := &proto.MemoryResult{
			Id:         r.ID.String(),
			Content:    r.Content,
			MemoryType: r.MemoryType,
			Namespace:  r.Namespace,
			ValidFrom:  r.ValidFrom.Format(time.RFC3339),
			Score:      r.Score,
		}
		if r.ValidUntil != nil {
			pr.ValidUntil = r.ValidUntil.Format(time.RFC3339)
		}
		protoResults = append(protoResults, pr)
	}

	return &proto.MemorySearchResponse{Results: protoResults}, nil
}

// Insert implements MemoryServiceServer.Insert.
// Forwards source_account_id and all content fields; returns the new row UUID.
func (h *MemoryHandler) Insert(ctx context.Context, req *proto.MemoryInsertRequest) (*proto.MemoryInsertResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, fmt.Errorf("memory handler: insert: invalid user_id %q: %w", req.UserId, err)
	}

	id, err := memory.MemoryInsert(ctx, h.db, userID, req.SourceAccountId, req.Content, req.Namespace, req.MemoryType)
	if err != nil {
		return nil, fmt.Errorf("memory handler: insert: %w", err)
	}

	return &proto.MemoryInsertResponse{Id: id.String()}, nil
}

// Replace implements MemoryServiceServer.Replace.
// Forwards source_account_id; authorize_token validation is TODO(E2).
func (h *MemoryHandler) Replace(ctx context.Context, req *proto.MemoryReplaceRequest) (*proto.MemoryReplaceResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, fmt.Errorf("memory handler: replace: invalid user_id %q: %w", req.UserId, err)
	}
	oldFactID, err := uuid.Parse(req.OldFactId)
	if err != nil {
		return nil, fmt.Errorf("memory handler: replace: invalid old_fact_id %q: %w", req.OldFactId, err)
	}

	// TODO(E2): validate req.AuthorizeToken against JWT claims before executing replace.
	// Dev bypass: NCLAW_DEV_BYPASS_AUTH=true skips validation in non-production envs.

	newID, err := memory.MemoryReplace(ctx, h.db, userID, req.SourceAccountId, oldFactID, req.NewContent, req.Namespace)
	if err != nil {
		return nil, fmt.Errorf("memory handler: replace: %w", err)
	}

	return &proto.MemoryReplaceResponse{NewId: newID.String()}, nil
}
