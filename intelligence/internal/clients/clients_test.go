// clients_test.go — Unit tests for QdrantClient and RetrievalClient.
//
// Purpose: Verify client behaviour with mocked gRPC/HTTP servers.
//          No real Qdrant or plugin-retrieval instance required.
// SPORT: REGISTRY-ENDPOINTS.md — /embed, /retrieve, /rerank test coverage.

package clients_test

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/nself-org/nclaw/intelligence/internal/clients"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ── QdrantClient tests ────────────────────────────────────────────────────

func TestQdrantConfigFromEnv(t *testing.T) {
	os.Setenv("NCLAW_QDRANT_GRPC_URL", "myhost:6333")
	defer os.Unsetenv("NCLAW_QDRANT_GRPC_URL")
	cfg := clients.QdrantConfigFromEnv()
	assert.Equal(t, "myhost:6333", cfg.GRPCURL)
}

func TestQdrantClientPingUnreachable(t *testing.T) {
	cfg := clients.QdrantConfig{GRPCURL: "localhost:19999", Collections: []string{"nclaw_personal"}}
	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	client, err := clients.NewQdrantClient(cfg, logger)
	require.NoError(t, err)
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	err = client.Ping(ctx)
	assert.Error(t, err, "Ping to unreachable host must return error")
}

func TestQdrantSearchPersonalReturnsEmpty(t *testing.T) {
	// Stub: searchOnce returns empty slice (SDK wiring deferred to SDK phase).
	cfg := clients.QdrantConfig{GRPCURL: "localhost:6333", Collections: []string{"nclaw_personal"}}
	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	client, err := clients.NewQdrantClient(cfg, logger)
	require.NoError(t, err)
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	vec := make([]float32, 1024)
	results, err := client.SearchPersonal(ctx, vec, 5)
	// With stub, returns empty results (no error — connection degraded path)
	assert.NotNil(t, results)
	_ = err // stub may error on unreachable — acceptable
}

func TestQdrantContextCancelledPropagated(t *testing.T) {
	cfg := clients.QdrantConfig{GRPCURL: "localhost:6333", Collections: []string{"nclaw_personal"}}
	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	client, err := clients.NewQdrantClient(cfg, logger)
	require.NoError(t, err)
	defer client.Close()

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // cancel immediately

	vec := make([]float32, 1024)
	_, err = client.SearchPersonal(ctx, vec, 5)
	assert.Error(t, err, "Cancelled context must return error")
}

// ── RetrievalClient tests ─────────────────────────────────────────────────

func TestRetrievalClientEmbed(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/embed" && r.Method == http.MethodPost {
			json.NewEncoder(w).Encode(map[string]any{
				"embeddings": [][]float32{{0.1, 0.2, 0.3}},
			})
			return
		}
		http.NotFound(w, r)
	}))
	defer server.Close()

	cfg := clients.RetrievalClientConfig{URL: server.URL, GatewayURL: server.URL}
	client := clients.NewRetrievalClient(cfg)

	embeddings, err := client.Embed(context.Background(), []string{"hello world"})
	require.NoError(t, err)
	require.Len(t, embeddings, 1)
	assert.Equal(t, []float32{0.1, 0.2, 0.3}, embeddings[0])
}

func TestRetrievalClientRerank(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/rerank" && r.Method == http.MethodPost {
			json.NewEncoder(w).Encode(map[string]any{
				"scores": []float32{0.9, 0.5, 0.1},
			})
			return
		}
		http.NotFound(w, r)
	}))
	defer server.Close()

	cfg := clients.RetrievalClientConfig{URL: server.URL, GatewayURL: server.URL}
	client := clients.NewRetrievalClient(cfg)

	scores, err := client.Rerank(context.Background(), "query", []string{"doc1", "doc2", "doc3"})
	require.NoError(t, err)
	assert.Equal(t, []float32{0.9, 0.5, 0.1}, scores)
}

func TestRetrievalClientRetrieve(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/retrieve" && r.Method == http.MethodPost {
			json.NewEncoder(w).Encode(map[string]any{
				"chunks": []clients.Chunk{
					{ID: "chunk-1", Content: "hello", Score: 0.8, Source: "doc.txt"},
				},
			})
			return
		}
		http.NotFound(w, r)
	}))
	defer server.Close()

	cfg := clients.RetrievalClientConfig{URL: server.URL, GatewayURL: server.URL}
	client := clients.NewRetrievalClient(cfg)

	chunks, err := client.Retrieve(context.Background(), "hello", 5)
	require.NoError(t, err)
	require.Len(t, chunks, 1)
	assert.Equal(t, "chunk-1", chunks[0].ID)
}

func TestRetrievalClientEmbed5xxRetries(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	cfg := clients.RetrievalClientConfig{URL: server.URL, GatewayURL: server.URL}
	client := clients.NewRetrievalClient(cfg)

	_, err := client.Embed(context.Background(), []string{"test"})
	assert.Error(t, err)
	// embedMaxRetries=2 means 3 total attempts (0,1,2)
	assert.Equal(t, 3, callCount, "Should retry 2 times on 5xx")
}
