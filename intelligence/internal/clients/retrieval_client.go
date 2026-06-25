// retrieval_client.go — HTTP client for the plugin-retrieval sidecar.
//
// Purpose: Wrap /embed, /retrieve, and /rerank endpoints on the plugin-retrieval
//          sidecar (port 3780 per F10-PORT-REGISTRY.md) and the canonical
//          nself-ai-gateway (port 3761 per gateway-unification-spec.md) for
//          AI model calls.
//
// Inputs:  RetrievalClientConfig from env vars, text inputs.
// Outputs: [][]float32 embeddings, []Chunk retrievals, []float32 reranker scores.
// Constraints: /embed 10s timeout + 2 retries; /retrieve + /rerank 5s + no retry.
//              Gateway calls use port 3761 — never legacy aliases.
//              Never log raw embedding floats.
// SPORT: REGISTRY-ENDPOINTS.md — /embed, /retrieve, /rerank at port 3780.

package clients

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const (
	embedTimeout    = 10 * time.Second
	retrieveTimeout = 5 * time.Second
	rerankTimeout   = 5 * time.Second
	embedMaxRetries = 2
)

// RetrievalClientConfig holds the base URL for the plugin-retrieval sidecar.
type RetrievalClientConfig struct {
	// URL is the base URL of the plugin-retrieval sidecar, e.g. "http://localhost:3780".
	URL string
	// GatewayURL is the canonical nself-ai-gateway base URL (port 3761).
	GatewayURL string
}

// RetrievalClientConfigFromEnv reads RetrievalClientConfig from environment.
func RetrievalClientConfigFromEnv() RetrievalClientConfig {
	url := os.Getenv("NCLAW_RETRIEVAL_URL")
	if url == "" {
		url = "http://localhost:3780"
	}
	gw := os.Getenv("NCLAW_GATEWAY_URL")
	if gw == "" {
		gw = "http://localhost:3761"
	}
	return RetrievalClientConfig{URL: url, GatewayURL: gw}
}

// Chunk is a single retrieved document chunk.
type Chunk struct {
	// ID is the chunk identifier.
	ID string `json:"id"`
	// Content is the text content of the chunk.
	Content string `json:"content"`
	// Score is the retrieval relevance score.
	Score float32 `json:"score"`
	// Source is the originating source reference.
	Source string `json:"source"`
}

// RetrievalClient wraps the plugin-retrieval HTTP sidecar.
type RetrievalClient struct {
	cfg    RetrievalClientConfig
	client *http.Client
}

// NewRetrievalClient creates a RetrievalClient with a shared HTTP client.
func NewRetrievalClient(cfg RetrievalClientConfig) *RetrievalClient {
	return &RetrievalClient{
		cfg:    cfg,
		client: &http.Client{}, // timeout set per-request below
	}
}

// Embed calls POST /embed on the plugin-retrieval sidecar.
// Returns one embedding vector per input text. Never logs raw float values.
// Retries up to embedMaxRetries times on 5xx or network error.
func (c *RetrievalClient) Embed(ctx context.Context, texts []string) ([][]float32, error) {
	body, _ := json.Marshal(map[string]any{"texts": texts})

	var lastErr error
	for attempt := 0; attempt <= embedMaxRetries; attempt++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		embeddings, err := c.postEmbed(ctx, body)
		if err == nil {
			return embeddings, nil
		}
		lastErr = err
	}
	return nil, fmt.Errorf("retrieval: embed after %d retries: %w", embedMaxRetries+1, lastErr)
}

func (c *RetrievalClient) postEmbed(ctx context.Context, body []byte) ([][]float32, error) {
	reqCtx, cancel := context.WithTimeout(ctx, embedTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, c.cfg.URL+"/embed", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 500 {
		return nil, fmt.Errorf("embed: server error %d", resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("embed: unexpected status %d", resp.StatusCode)
	}

	var result struct {
		Embeddings [][]float32 `json:"embeddings"`
	}
	data, _ := io.ReadAll(resp.Body)
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("embed: decode response: %w", err)
	}
	return result.Embeddings, nil
}

// Retrieve calls POST /retrieve on the plugin-retrieval sidecar.
// Returns up to topK document chunks ranked by relevance.
func (c *RetrievalClient) Retrieve(ctx context.Context, query string, topK int) ([]Chunk, error) {
	body, _ := json.Marshal(map[string]any{"query": query, "top_k": topK})

	reqCtx, cancel := context.WithTimeout(ctx, retrieveTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, c.cfg.URL+"/retrieve", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("retrieve: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("retrieve: unexpected status %d", resp.StatusCode)
	}

	var result struct {
		Chunks []Chunk `json:"chunks"`
	}
	data, _ := io.ReadAll(resp.Body)
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("retrieve: decode response: %w", err)
	}
	return result.Chunks, nil
}

// Rerank calls POST /rerank on the plugin-retrieval sidecar.
// Returns relevance scores for each doc, aligned by index.
func (c *RetrievalClient) Rerank(ctx context.Context, query string, docs []string) ([]float32, error) {
	body, _ := json.Marshal(map[string]any{"query": query, "documents": docs})

	reqCtx, cancel := context.WithTimeout(ctx, rerankTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, c.cfg.URL+"/rerank", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("rerank: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("rerank: unexpected status %d", resp.StatusCode)
	}

	var result struct {
		Scores []float32 `json:"scores"`
	}
	data, _ := io.ReadAll(resp.Body)
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("rerank: decode response: %w", err)
	}
	return result.Scores, nil
}
