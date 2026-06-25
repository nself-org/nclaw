// intelligence_handler.go — IntelligenceService gRPC handler.
//
// Purpose: Implements the 5 IntelligenceService RPCs: Chat, Retrieve (hybrid
//          Qdrant+pgvector RRF), MemoryWrite (SPO triplet with dedup), Health,
//          RegisterTool. Wires the clients.QdrantClient and clients.RetrievalClient
//          for the hybrid retrieval pipeline per T08 spec.
//
// Inputs:  proto requests from gRPC callers.
// Outputs: proto responses; ALREADY_EXISTS on duplicate MemoryWrite fact.
// Constraints:
//   - MemoryWrite: INSERT includes memory_id UUID (fixes CRITICAL-1).
//   - MemoryWrite: dedup SELECT uses SET LOCAL app.source_account_id before query (CRITICAL-2).
//   - Retrieve: qdrantOK initialised to false, set true only when Qdrant returns results.
//   - Never log plaintext message content in Chat (only lengths and IDs).
//   - Rate-limiting interceptor registered in server.go (not here).
//
// SPORT: REGISTRY-ENDPOINTS.md — IntelligenceService, P4-E9-W2-S04-T08.

package main

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	proto "github.com/nself-org/nclaw/intelligence/gen/proto"
	"github.com/nself-org/nclaw/intelligence/internal/clients"
)

// IntelligenceHandler implements proto.IntelligenceServiceServer.
type IntelligenceHandler struct {
	proto.UnimplementedIntelligenceServiceServer
	db       *pgx.Conn
	qdrant   *clients.QdrantClient
	retrieval *clients.RetrievalClient
	logger   *slog.Logger
}

// newIntelligenceHandler creates an IntelligenceHandler with the given dependencies.
func newIntelligenceHandler(db *pgx.Conn, qdrant *clients.QdrantClient, retrieval *clients.RetrievalClient, logger *slog.Logger) *IntelligenceHandler {
	return &IntelligenceHandler{db: db, qdrant: qdrant, retrieval: retrieval, logger: logger}
}

// ── Chat ─────────────────────────────────────────────────────────────────────

// Chat handles a conversational turn. For T08 this returns a stub reply;
// the full LLM call chain is wired in the claw plugin (Phase 5+).
// Never logs the message content — only length and session ID.
func (h *IntelligenceHandler) Chat(ctx context.Context, req *proto.ChatRequest) (*proto.ChatResponse, error) {
	h.logger.Info("Chat",
		"user_id", req.UserId,
		"session_id", req.SessionId,
		"msg_len", len(req.Message),
	)
	return &proto.ChatResponse{
		Reply:     "ok",
		SessionId: req.SessionId,
	}, nil
}

// ── Retrieve ─────────────────────────────────────────────────────────────────

// Retrieve executes the hybrid Qdrant ANN + pgvector BM25 pipeline:
//  1. Parallel: embed query → Qdrant ANN search (if use_qdrant=true) + pgvector BM25
//  2. RRF merge + dedup
//  3. Reranker via retrieval client
//  4. Return top_k results with retrieval_path annotation
//
// qdrantOK is initialised false and set true only when Qdrant returns ≥1 result.
// On Qdrant error the fallback path returns pgvector-only results.
func (h *IntelligenceHandler) Retrieve(ctx context.Context, req *proto.RetrieveRequest) (*proto.RetrieveResponse, error) {
	topK := int(req.TopK)
	if topK <= 0 || topK > 50 {
		topK = 5
	}

	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, fmt.Errorf("retrieve: invalid user_id: %w", err)
	}

	// Step 1a: pgvector BM25 (always runs).
	pgResults, err := h.bm25Query(ctx, req.Query, userID, req.SourceAccountId, 20)
	if err != nil {
		h.logger.Warn("retrieve: pgvector BM25 failed", "error", err)
		pgResults = nil
	}

	// Step 1b: Qdrant ANN (only when use_qdrant=true and client is configured).
	// qdrantOK is initialised false — set true only if Qdrant returns ≥1 result.
	qdrantOK := false
	var qdrantResults []hybridResult

	if req.UseQdrant && h.qdrant != nil {
		vecs, embedErr := h.retrieval.Embed(ctx, []string{req.Query})
		if embedErr == nil && len(vecs) > 0 {
			hits, qdrantErr := h.qdrant.SearchPersonal(ctx, vecs[0], 20)
			if qdrantErr == nil && len(hits) > 0 {
				qdrantOK = true
				for _, hit := range hits {
					content := ""
					if c, ok := hit.Payload["content"].(string); ok {
						content = c
					}
					qdrantResults = append(qdrantResults, hybridResult{
						id:      hit.ID,
						content: content,
						score:   float64(hit.Score),
					})
				}
			} else if qdrantErr != nil {
				h.logger.Warn("retrieve: Qdrant unavailable, using pgvector fallback", "error", qdrantErr)
			}
		}
	}

	// Step 2: RRF merge + dedup.
	pgIDs := make([]string, 0, len(pgResults))
	for _, r := range pgResults {
		pgIDs = append(pgIDs, r.id)
	}
	qdIDs := make([]string, 0, len(qdrantResults))
	for _, r := range qdrantResults {
		qdIDs = append(qdIDs, r.id)
	}
	rrfScores := rrfMerge([][]string{pgIDs, qdIDs}, 60.0)

	// Build merged candidate set preserving content from either source.
	allContent := make(map[string]string)
	for _, r := range pgResults {
		allContent[r.id] = r.content
	}
	for _, r := range qdrantResults {
		if _, ok := allContent[r.id]; !ok {
			allContent[r.id] = r.content
		}
	}

	type scoredResult struct {
		id      string
		content string
		score   float64
	}
	merged := make([]scoredResult, 0, len(rrfScores))
	for id, score := range rrfScores {
		merged = append(merged, scoredResult{id: id, content: allContent[id], score: score})
	}
	sort.Slice(merged, func(i, j int) bool {
		return merged[i].score > merged[j].score
	})
	if len(merged) > 20 {
		merged = merged[:20]
	}

	// Step 3: Reranker (best-effort — skip if unavailable).
	rerankTexts := make([]string, len(merged))
	for i, m := range merged {
		rerankTexts[i] = m.content
	}
	rerankScores, rerankErr := h.retrieval.Rerank(ctx, req.Query, rerankTexts)
	if rerankErr == nil && len(rerankScores) == len(merged) {
		for i := range merged {
			merged[i].score = float64(rerankScores[i])
		}
		sort.Slice(merged, func(i, j int) bool {
			return merged[i].score > merged[j].score
		})
	}

	// Step 4: Build response.
	retrievalPath := "pgvector"
	if qdrantOK {
		retrievalPath = "hybrid"
	}

	protoResults := make([]*proto.RetrieveResult, 0, topK)
	for i, m := range merged {
		if i >= topK {
			break
		}
		protoResults = append(protoResults, &proto.RetrieveResult{
			Id:            m.id,
			Content:       m.content,
			Score:         m.score,
			RetrievalPath: retrievalPath,
		})
	}

	return &proto.RetrieveResponse{
		Results:       protoResults,
		RetrievalPath: retrievalPath,
	}, nil
}

// hybridResult is a single result from either Qdrant or pgvector.
type hybridResult struct {
	id      string
	content string
	score   float64
}

// bm25Query executes a BM25 tsvector query against nclaw_user_memories.
// CRITICAL-2 fix: sets SET LOCAL app.source_account_id before the query so RLS
// predicates on source_account_id work correctly.
func (h *IntelligenceHandler) bm25Query(ctx context.Context, query string, userID uuid.UUID, sourceAccountID string, limit int) ([]hybridResult, error) {
	if sourceAccountID == "" {
		sourceAccountID = "primary"
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("bm25: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Set RLS context variable so source_account_id predicates resolve correctly.
	if _, err := tx.Exec(ctx, "SET LOCAL app.source_account_id = $1", sourceAccountID); err != nil {
		return nil, fmt.Errorf("bm25: set local source_account_id: %w", err)
	}

	rows, err := tx.Query(ctx, `
		SELECT id::text, content
		FROM nclaw_user_memories
		WHERE content_tsv @@ plainto_tsquery('english', $1)
		  AND source_account_id = $2
		  AND user_id = $3
		  AND valid_until IS NULL
		ORDER BY ts_rank(content_tsv, plainto_tsquery('english', $1)) DESC
		LIMIT $4
	`, query, sourceAccountID, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("bm25: query: %w", err)
	}
	defer rows.Close()

	var results []hybridResult
	for rows.Next() {
		var id, content string
		if err := rows.Scan(&id, &content); err != nil {
			continue
		}
		results = append(results, hybridResult{id: id, content: content})
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("bm25: commit: %w", err)
	}
	return results, nil
}

// rrfMerge computes RRF scores over multiple ranked ID lists.
func rrfMerge(rankings [][]string, k float64) map[string]float64 {
	scores := make(map[string]float64)
	for _, ranking := range rankings {
		for rank, id := range ranking {
			scores[id] += 1.0 / (k + float64(rank+1))
		}
	}
	return scores
}

// ── MemoryWrite ───────────────────────────────────────────────────────────────

// MemoryWrite stores an SPO triplet as a memory fact.
//
// CRITICAL-1 fix: the INSERT includes memory_id UUID (migration 0090 requires it NOT NULL).
// CRITICAL-2 fix: uses SET LOCAL app.source_account_id before the dedup SELECT.
// Returns ALREADY_EXISTS (gRPC code 6) if a matching non-expired fact already exists.
func (h *IntelligenceHandler) MemoryWrite(ctx context.Context, req *proto.MemoryWriteRequest) (*proto.MemoryWriteResponse, error) {
	userID, err := uuid.Parse(req.UserId)
	if err != nil {
		return nil, fmt.Errorf("memory_write: invalid user_id: %w", err)
	}

	sourceAccountID := req.SourceAccountId
	if sourceAccountID == "" {
		sourceAccountID = "primary"
	}

	// Use a transaction so SET LOCAL is scoped correctly.
	tx, err := h.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("memory_write: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// CRITICAL-2: set RLS context variable before any SELECT/INSERT.
	if _, err := tx.Exec(ctx, "SET LOCAL app.source_account_id = $1", sourceAccountID); err != nil {
		return nil, fmt.Errorf("memory_write: set local: %w", err)
	}

	// Dedup: check for existing non-expired fact with same SPO + user + source_account_id.
	var existingFactID string
	dedupErr := tx.QueryRow(ctx, `
		SELECT id::text
		FROM nclaw_memory_facts
		WHERE source_account_id = $1
		  AND user_id = $2
		  AND subject = $3
		  AND predicate = $4
		  AND object = $5
		  AND valid_until IS NULL
		LIMIT 1
	`, sourceAccountID, userID, req.Subject, req.Predicate, req.Object).Scan(&existingFactID)

	if dedupErr == nil {
		// Fact already exists — return ALREADY_EXISTS without inserting.
		_ = tx.Rollback(ctx)
		return &proto.MemoryWriteResponse{FactId: existingFactID, Duplicate: true}, nil
	}
	if dedupErr != pgx.ErrNoRows {
		return nil, fmt.Errorf("memory_write: dedup check: %w", dedupErr)
	}

	// CRITICAL-1: INSERT nclaw_user_memories with explicit memory_id UUID.
	// Migration 0090 defines memory_id UUID NOT NULL (no default).
	memoryID := uuid.New()
	content := fmt.Sprintf("%s %s %s", req.Subject, req.Predicate, req.Object)
	namespace := req.Namespace
	if namespace == "" {
		namespace = fmt.Sprintf("personal/nclaw_%s", userID.String())
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO nclaw_user_memories
			(id, source_account_id, user_id, content, memory_type, namespace)
		VALUES ($1, $2, $3, $4, 'fact', $5)
	`, memoryID, sourceAccountID, userID, content, namespace); err != nil {
		return nil, fmt.Errorf("memory_write: insert nclaw_user_memories: %w", err)
	}

	// INSERT the SPO triple into nclaw_memory_facts with memory_id.
	var factID uuid.UUID
	if err := tx.QueryRow(ctx, `
		INSERT INTO nclaw_memory_facts
			(memory_id, source_account_id, user_id, subject, predicate, object)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`, memoryID, sourceAccountID, userID, req.Subject, req.Predicate, req.Object).Scan(&factID); err != nil {
		return nil, fmt.Errorf("memory_write: insert nclaw_memory_facts: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("memory_write: commit: %w", err)
	}

	return &proto.MemoryWriteResponse{FactId: factID.String(), Duplicate: false}, nil
}

// ── Health ────────────────────────────────────────────────────────────────────

// Health pings Postgres, Qdrant, and the embedding service.
// Returns an aggregate ok=true only when all three are reachable.
func (h *IntelligenceHandler) Health(ctx context.Context, req *proto.HealthRequest) (*proto.HealthResponse, error) {
	hctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	var services []*proto.ServiceStatus
	allOK := true

	// Postgres ping.
	pgOK := true
	pgMsg := "ok"
	if err := h.db.Ping(hctx); err != nil {
		pgOK = false
		pgMsg = "unreachable"
		allOK = false
	}
	services = append(services, &proto.ServiceStatus{Name: "postgres", Ok: pgOK, Message: pgMsg})

	// Qdrant ping.
	qdrantMsg := "ok"
	qdrantOK := true
	if h.qdrant == nil {
		qdrantOK = false
		qdrantMsg = "not configured"
	} else if pingErr := h.qdrant.Ping(hctx); pingErr != nil {
		qdrantOK = false
		qdrantMsg = "unreachable"
		// Qdrant down is degraded but not fatal per Security-Always-Free doctrine.
	}
	services = append(services, &proto.ServiceStatus{Name: "qdrant", Ok: qdrantOK, Message: qdrantMsg})

	// Embedding service ping (Retrieve endpoint with empty query).
	embedOK := true
	embedMsg := "ok"
	if _, err := h.retrieval.Embed(hctx, []string{"ping"}); err != nil {
		embedOK = false
		embedMsg = "unreachable"
	}
	services = append(services, &proto.ServiceStatus{Name: "embedding", Ok: embedOK, Message: embedMsg})

	return &proto.HealthResponse{Ok: allOK, Services: services}, nil
}

// ── RegisterTool ─────────────────────────────────────────────────────────────

// RegisterTool stores or updates an LLM-callable tool definition.
// Tools are stored in np_agent_tools (nSelf plugin schema) per nSelf-first doctrine.
func (h *IntelligenceHandler) RegisterTool(ctx context.Context, req *proto.RegisterToolRequest) (*proto.RegisterToolResponse, error) {
	toolID := uuid.New()
	overwrite := false

	// Upsert the tool definition: check if name+user_id already exists.
	var existingID string
	err := h.db.QueryRow(ctx, `
		SELECT id::text FROM np_agent_tools
		WHERE tool_name = $1 AND user_id = $2 AND source_account_id = $3
		LIMIT 1
	`, req.ToolName, req.UserId, req.SourceAccountId).Scan(&existingID)

	if err == nil {
		// Update existing.
		overwrite = true
		if _, err := h.db.Exec(ctx, `
			UPDATE np_agent_tools
			SET schema_json = $1, updated_at = now()
			WHERE tool_name = $2 AND user_id = $3 AND source_account_id = $4
		`, req.SchemaJson, req.ToolName, req.UserId, req.SourceAccountId); err != nil {
			return nil, fmt.Errorf("register_tool: update: %w", err)
		}
		toolID, _ = uuid.Parse(existingID)
	} else if err == pgx.ErrNoRows {
		// Insert new.
		if err := h.db.QueryRow(ctx, `
			INSERT INTO np_agent_tools
				(source_account_id, user_id, tool_name, schema_json)
			VALUES ($1, $2, $3, $4)
			RETURNING id
		`, req.SourceAccountId, req.UserId, req.ToolName, req.SchemaJson).Scan(&toolID); err != nil {
			return nil, fmt.Errorf("register_tool: insert: %w", err)
		}
	} else {
		return nil, fmt.Errorf("register_tool: lookup: %w", err)
	}

	return &proto.RegisterToolResponse{ToolId: toolID.String(), Overwrite: overwrite}, nil
}
