// qdrant.go — Qdrant HTTP client for vector upsert and search.
//
// Purpose: Thin net/http wrapper for Qdrant REST API. Provides QdrantUpsert
//          (insert/update a point with vector + payload) and QdrantSearch
//          (ANN search returning top-K matches with optional payload filter).
// Inputs:  collection string, id string, vector []float32, payload map[string]any,
//          topK int, filter map[string]any (optional).
// Outputs: error for upsert; []QdrantMatch for search.
// Constraints: No external Qdrant SDK — only net/http. Env: NCLAW_QDRANT_URL.
//              Embed via NCLAW_EMBED_URL GET /embed?text=<query>.
// SPORT: nclaw-memory-architecture-spec.md §6 — Qdrant dense retrieval path.
package memory

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"
)

// QdrantMatch represents a single result from a Qdrant vector search.
type QdrantMatch struct {
	// ID is the point identifier (document ID string).
	ID string
	// Score is the cosine similarity score returned by Qdrant.
	Score float64
	// Payload contains arbitrary metadata stored with the point.
	Payload map[string]any
}

var qdrantHTTPClient = &http.Client{Timeout: 10 * time.Second}

// QdrantUpsert inserts or updates a vector point in the given Qdrant collection.
//
// Reads NCLAW_QDRANT_URL from the environment. The id must be a UUID-compatible string.
// On non-2xx response the returned error includes the HTTP status and body excerpt.
func QdrantUpsert(ctx context.Context, collection string, id string, vector []float32, payload map[string]any) error {
	base := os.Getenv("NCLAW_QDRANT_URL")
	if base == "" {
		return fmt.Errorf("qdrant: NCLAW_QDRANT_URL not set")
	}

	body := map[string]any{
		"points": []map[string]any{
			{
				"id":      id,
				"vector":  vector,
				"payload": payload,
			},
		},
	}
	b, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("qdrant: marshal upsert body: %w", err)
	}

	endpoint := fmt.Sprintf("%s/collections/%s/points", base, url.PathEscape(collection))
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, endpoint, bytes.NewReader(b))
	if err != nil {
		return fmt.Errorf("qdrant: build upsert request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := qdrantHTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("qdrant: upsert request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("qdrant: upsert HTTP %d: %s", resp.StatusCode, snippet)
	}
	return nil
}

// QdrantSearch performs approximate nearest-neighbour search in the given collection.
//
// Reads NCLAW_QDRANT_URL from the environment. filter is a Qdrant filter object
// (e.g. {"must": [{"key": "org_slug", "match": {"value": "acme"}}]}) — pass nil for no filter.
// Returns up to topK matches ordered by descending score.
func QdrantSearch(ctx context.Context, collection string, vector []float32, topK int, filter map[string]any) ([]QdrantMatch, error) {
	base := os.Getenv("NCLAW_QDRANT_URL")
	if base == "" {
		return nil, fmt.Errorf("qdrant: NCLAW_QDRANT_URL not set")
	}

	body := map[string]any{
		"vector":       vector,
		"limit":        topK,
		"with_payload": true,
	}
	if filter != nil {
		body["filter"] = filter
	}

	b, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("qdrant: marshal search body: %w", err)
	}

	endpoint := fmt.Sprintf("%s/collections/%s/points/search", base, url.PathEscape(collection))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(b))
	if err != nil {
		return nil, fmt.Errorf("qdrant: build search request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := qdrantHTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("qdrant: search request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("qdrant: search HTTP %d: %s", resp.StatusCode, snippet)
	}

	var result struct {
		Result []struct {
			ID      any            `json:"id"`
			Score   float64        `json:"score"`
			Payload map[string]any `json:"payload"`
		} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("qdrant: decode search response: %w", err)
	}

	matches := make([]QdrantMatch, 0, len(result.Result))
	for _, r := range result.Result {
		id := fmt.Sprintf("%v", r.ID)
		matches = append(matches, QdrantMatch{ID: id, Score: r.Score, Payload: r.Payload})
	}
	return matches, nil
}

// EmbedText encodes a query string to a float32 vector using the embedding service.
//
// Reads NCLAW_EMBED_URL from the environment. Calls GET /embed?text=<query>.
// Returns nil vector and an error if the env var is unset or the call fails.
func EmbedText(ctx context.Context, text string) ([]float32, error) {
	base := os.Getenv("NCLAW_EMBED_URL")
	if base == "" {
		return nil, fmt.Errorf("qdrant: NCLAW_EMBED_URL not set")
	}

	endpoint := fmt.Sprintf("%s/embed?text=%s", base, url.QueryEscape(text))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("qdrant: build embed request: %w", err)
	}

	resp, err := qdrantHTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("qdrant: embed request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("qdrant: embed HTTP %d: %s", resp.StatusCode, snippet)
	}

	var payload struct {
		Embedding []float32 `json:"embedding"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("qdrant: decode embed response: %w", err)
	}
	return payload.Embedding, nil
}
