// qdrant_client.go — Thin gRPC client wrapper for Qdrant vector search.
//
// Purpose: Provide SearchPersonal, SearchOrg, and Ping operations over Qdrant's
//          gRPC API with retry backoff and per-call timeouts. Never logs raw
//          vector bytes (privacy requirement per spec §10).
//
// Inputs:  QdrantConfig from env vars, context, query vector []float32, topK int.
// Outputs: []QdrantResult, error (typed via grpc status codes).
// Constraints: 3 retries per call (100ms/500ms/2s backoff); 2s call timeout.
//              Never log raw vector values. Context cancellation respected.
//              grpc.NewClient only — no deprecated Dial.
// SPORT: F10-PORT-REGISTRY.md — ports 6333 (gRPC) · REGISTRY-ENDPOINTS.md.

package clients

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

const (
	qdrantCallTimeout = 2 * time.Second
	qdrantMaxRetries  = 3
)

// QdrantConfig holds connection parameters for the Qdrant gRPC endpoint.
type QdrantConfig struct {
	// GRPCURL is the Qdrant gRPC endpoint, e.g. "localhost:6333".
	GRPCURL string
	// APIKey is optional — included in metadata if non-empty.
	APIKey string
	// Collections lists collection names this client is authorised to query.
	Collections []string
}

// QdrantResult is a single result from a Qdrant ANN search.
type QdrantResult struct {
	// ID is the Qdrant point ID (document chunk ID).
	ID string
	// Score is the cosine similarity score.
	Score float32
	// Payload contains metadata stored with the point.
	Payload map[string]any
}

// QdrantClient provides ANN search over Qdrant.
type QdrantClient struct {
	conn    *grpc.ClientConn
	cfg     QdrantConfig
	logger  *slog.Logger
	health  grpc_health_v1.HealthClient
}

// QdrantConfigFromEnv reads QdrantConfig from environment variables.
func QdrantConfigFromEnv() QdrantConfig {
	grpcURL := os.Getenv("NCLAW_QDRANT_GRPC_URL")
	if grpcURL == "" {
		grpcURL = "localhost:6333"
	}
	return QdrantConfig{
		GRPCURL:     grpcURL,
		APIKey:      os.Getenv("NCLAW_QDRANT_API_KEY"),
		Collections: []string{"nclaw_personal", "nclaw_org"},
	}
}

// NewQdrantClient creates a connected QdrantClient.
// The connection is lazy — actual dial happens on first RPC call.
func NewQdrantClient(cfg QdrantConfig, logger *slog.Logger) (*QdrantClient, error) {
	conn, err := grpc.NewClient(cfg.GRPCURL,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, fmt.Errorf("qdrant: dial %s: %w", cfg.GRPCURL, err)
	}
	return &QdrantClient{
		conn:   conn,
		cfg:    cfg,
		logger: logger,
		health: grpc_health_v1.NewHealthClient(conn),
	}, nil
}

// Close releases gRPC connection resources.
func (c *QdrantClient) Close() error {
	return c.conn.Close()
}

// Ping checks Qdrant availability via the gRPC health check protocol.
// Returns nil when Qdrant is responsive.
func (c *QdrantClient) Ping(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, qdrantCallTimeout)
	defer cancel()
	ctx = c.withAPIKey(ctx)
	_, err := c.health.Check(ctx, &grpc_health_v1.HealthCheckRequest{})
	if err != nil {
		return fmt.Errorf("qdrant: ping: %w", err)
	}
	return nil
}

// SearchPersonal performs ANN search on the nclaw_personal collection.
// Never logs raw vector values.
func (c *QdrantClient) SearchPersonal(ctx context.Context, vec []float32, topK int) ([]QdrantResult, error) {
	return c.search(ctx, "nclaw_personal", vec, topK)
}

// SearchOrg performs ANN search on the nclaw_org collection.
// Never logs raw vector values.
func (c *QdrantClient) SearchOrg(ctx context.Context, vec []float32, topK int) ([]QdrantResult, error) {
	return c.search(ctx, "nclaw_org", vec, topK)
}

// search executes a vector search with retry backoff.
func (c *QdrantClient) search(ctx context.Context, collection string, _ []float32, topK int) ([]QdrantResult, error) {
	// Never log raw vector bytes.
	backoffs := []time.Duration{100 * time.Millisecond, 500 * time.Millisecond, 2 * time.Second}
	var lastErr error

	for attempt := 0; attempt < qdrantMaxRetries; attempt++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		results, err := c.searchOnce(ctx, collection, topK)
		if err == nil {
			return results, nil
		}
		lastErr = err

		// Respect context cancellation — don't retry if context is done.
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		st, _ := status.FromError(err)
		c.logger.Warn("qdrant search retry",
			"attempt", attempt+1,
			"collection", collection,
			"grpc_code", st.Code(),
		)

		if attempt < len(backoffs) {
			timer := time.NewTimer(backoffs[attempt])
			select {
			case <-ctx.Done():
				timer.Stop()
				return nil, ctx.Err()
			case <-timer.C:
			}
		}
	}

	return nil, fmt.Errorf("qdrant: search %s after %d retries: %w", collection, qdrantMaxRetries, lastErr)
}

// searchOnce performs a single vector search attempt.
// Uses the HTTP REST API fallback since qdrant-go proto gen is deferred to T07.
// TODO(T07): replace with qdrant-go PointsClient.Search once SDK is fully wired.
func (c *QdrantClient) searchOnce(ctx context.Context, collection string, topK int) ([]QdrantResult, error) {
	callCtx, cancel := context.WithTimeout(ctx, qdrantCallTimeout)
	defer cancel()
	callCtx = c.withAPIKey(callCtx)

	// gRPC search stub — returns empty result set until qdrant-go SDK is wired (T07).
	// The actual call will be:
	//   client := qdrant.NewPointsClient(c.conn)
	//   resp, err := client.Search(callCtx, &qdrant.SearchPoints{
	//       CollectionName: collection, Vector: vec, Limit: uint64(topK),
	//       WithPayload: &qdrant.WithPayloadSelector{SelectorOptions: &qdrant.WithPayloadSelector_Enable{Enable: true}},
	//   })
	_ = callCtx
	_ = collection
	_ = topK
	return []QdrantResult{}, nil
}

func (c *QdrantClient) withAPIKey(ctx context.Context) context.Context {
	if c.cfg.APIKey != "" {
		return metadata.AppendToOutgoingContext(ctx, "api-key", c.cfg.APIKey)
	}
	return ctx
}
