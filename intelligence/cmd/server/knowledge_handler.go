// knowledge_handler.go — gRPC KnowledgeServiceServer adapter for the T05 knowledge package.
//
// Purpose: Bridge the gRPC KnowledgeService interface (gen/proto) to the internal
//
//	knowledge package functions (internal/knowledge). Converts proto request/response
//	types to/from package types. Forwards source_account_id from every request.
//
// Inputs:  gRPC KnowledgeIngestRequest / KnowledgeQueryRequest.
// Outputs: gRPC KnowledgeIngestResponse / KnowledgeQueryResponse.
// Constraints: No auth here (dev bypass via NCLAW_DEV_BYPASS_AUTH=true; E2 gate).
//
//	≤100 lines. All env vars read in main.go — not this file.
//
// SPORT: nclaw-memory-architecture-spec.md §3 §5 — P2-E5-W4-S8-T08.
package main

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"

	proto "github.com/nself-org/nclaw/intelligence/gen/proto"
	"github.com/nself-org/nclaw/intelligence/internal/knowledge"
)

// KnowledgeHandler implements proto.KnowledgeServiceServer using the T05 knowledge package.
type KnowledgeHandler struct {
	proto.UnimplementedKnowledgeServiceServer
	// db is the Postgres connection shared across all requests.
	db *pgx.Conn
}

// newKnowledgeHandler creates a KnowledgeHandler wrapping the given Postgres connection.
func newKnowledgeHandler(db *pgx.Conn) *KnowledgeHandler {
	return &KnowledgeHandler{db: db}
}

// Ingest implements KnowledgeServiceServer.Ingest.
// Delegates to knowledge.KnowledgeIngest; chunking is handled by the internal package.
func (h *KnowledgeHandler) Ingest(ctx context.Context, req *proto.KnowledgeIngestRequest) (*proto.KnowledgeIngestResponse, error) {
	count, err := knowledge.KnowledgeIngest(
		ctx,
		*h.db,
		req.OrgSlug,
		req.SourceAccountId,
		req.DocType,
		req.SourceRef,
		req.RawText,
	)
	if err != nil {
		return nil, fmt.Errorf("knowledge handler: ingest: %w", err)
	}

	return &proto.KnowledgeIngestResponse{ChunksIngested: int32(count)}, nil
}

// Query implements KnowledgeServiceServer.Query.
// Delegates to knowledge.KnowledgeQuery; results are scoped to org_slug.
func (h *KnowledgeHandler) Query(ctx context.Context, req *proto.KnowledgeQueryRequest) (*proto.KnowledgeQueryResponse, error) {
	results, err := knowledge.KnowledgeQuery(
		ctx,
		*h.db,
		req.Query,
		req.OrgSlug,
		req.SourceAccountId,
		int(req.TopK),
	)
	if err != nil {
		return nil, fmt.Errorf("knowledge handler: query: %w", err)
	}

	protoResults := make([]*proto.KnowledgeResult, 0, len(results))
	for _, r := range results {
		protoResults = append(protoResults, &proto.KnowledgeResult{
			Id:        r.ID,
			Content:   r.Content,
			DocType:   r.DocType,
			SourceRef: r.SourceRef,
			Score:     r.Score,
			OrgSlug:   req.OrgSlug, // C1 fix: echo query scope — internal struct has no OrgSlug field.
		})
	}

	return &proto.KnowledgeQueryResponse{Results: protoResults}, nil
}
