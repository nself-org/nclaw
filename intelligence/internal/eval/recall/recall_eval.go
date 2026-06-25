package recall

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"
)

// RecallQualityEval runs memory recall quality evaluation for ɳClaw.
// Purpose: Ground-truth validation of BGE-M3 + reranker hybrid search quality.
//   Measures how accurately nclaw_memory_facts retrieval surfaces golden triples.
//
// IMPORTANT — OD-E4-01 Synthetic-Only Constraint:
//   This runner ONLY operates on synthetic golden sets curated in nclaw/.claude/evals/golden/.
//   It MUST NEVER be called with real user memory IDs or real user query data.
//   Real user memory is E2EE; eval harness operates only on bounded non-sensitive golden data.
//
// Inputs: retrieval endpoint (plugin-retrieval hybrid search), k, golden triple set.
// Outputs: RecallQualityResult with precision@k, recall@k, fact_f1, faithfulness.
// Constraints: Requires plugin-retrieval with BGE-M3 wired (E3 precondition).
type RecallQualityEval struct {
	// RetrievalURL is the plugin-retrieval hybrid search endpoint.
	// Example: "http://localhost:3771/retrieve"
	RetrievalURL string
	// EmbedURL is the plugin-retrieval embed endpoint for faithfulness scoring.
	EmbedURL string
	// Timeout is per-call timeout for retrieval and embed calls.
	Timeout time.Duration
	// HTTPClient is injectable for testing.
	HTTPClient *http.Client
	// K is the default number of top results to retrieve.
	K int
}

// retrievalRequest is sent to plugin-retrieval for hybrid memory search.
type retrievalRequest struct {
	Query string `json:"query"`
	K     int    `json:"k"`
	Model string `json:"model"`
}

// retrievalResponse is the response from plugin-retrieval hybrid search.
type retrievalResponse struct {
	Facts []retrievedFact `json:"facts"`
}

// retrievedFact is a single memory fact from retrieval results.
type retrievedFact struct {
	ID        string  `json:"id"`
	Subject   string  `json:"subject"`
	Predicate string  `json:"predicate"`
	Object    string  `json:"object"`
	Score     float64 `json:"score"`
	IsGolden  bool    `json:"is_golden"`
}

// Run executes the full recall-quality eval algorithm.
// Purpose: Given a golden query and golden triple set, measure retrieval quality.
// Inputs: ctx, query (golden query string), goldenTriples (ground truth), k (top-k).
// Outputs: RecallQualityResult with all four metrics populated.
// Constraints: If plugin-retrieval unavailable, returns ErrPreconditionNotMet equivalent.
//
// Algorithm (per spec §5c):
//  1. Query nclaw_memory_facts via plugin-retrieval hybrid search (pgvector+tsvector+RRF+BGE-M3).
//  2. Take top-k; extract triples.
//  3. Compute precision@k, recall@k, fact_f1.
//  4. Compute faithfulness via rubric scoring (cosine of generated answer vs golden).
func (e *RecallQualityEval) Run(ctx context.Context, query string, goldenTriples []Triple, k int) (RecallQualityResult, error) {
	if k <= 0 {
		k = e.K
	}
	if k <= 0 {
		k = 3
	}

	client := e.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: e.Timeout}
	}

	// Step 1: Query plugin-retrieval for top-k memory facts.
	reqBody, err := json.Marshal(retrievalRequest{
		Query: query,
		K:     k,
		Model: "bge-m3",
	})
	if err != nil {
		return RecallQualityResult{}, fmt.Errorf("recall eval marshal request: %w", err)
	}

	reqCtx, cancel := context.WithTimeout(ctx, e.Timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, e.RetrievalURL, bytes.NewReader(reqBody))
	if err != nil {
		return RecallQualityResult{}, fmt.Errorf("recall eval build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return RecallQualityResult{}, fmt.Errorf("recall eval retrieval unavailable: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return RecallQualityResult{}, fmt.Errorf("recall eval retrieval HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return RecallQualityResult{}, fmt.Errorf("recall eval read response: %w", err)
	}

	var retrievalResp retrievalResponse
	if err := json.Unmarshal(body, &retrievalResp); err != nil {
		return RecallQualityResult{}, fmt.Errorf("recall eval parse response: %w", err)
	}

	// Step 2: Extract triples from retrieved facts.
	rows := make([]MemoryFactRow, len(retrievalResp.Facts))
	for i, f := range retrievalResp.Facts {
		rows[i] = MemoryFactRow{
			ID:        f.ID,
			Subject:   f.Subject,
			Predicate: f.Predicate,
			Object:    f.Object,
			IsGolden:  f.IsGolden,
		}
	}
	retrievedTriples := ExtractTriples(rows)

	// Limit to k triples.
	if len(retrievedTriples) > k {
		retrievedTriples = retrievedTriples[:k]
	}

	// Step 3: Compute precision@k, recall@k, fact_f1.
	intersection := tripleIntersectionCount(retrievedTriples, goldenTriples)
	precisionAtK := float64(intersection) / float64(k)
	if k == 0 {
		precisionAtK = 0.0
	}
	recallAtK := 0.0
	if len(goldenTriples) > 0 {
		recallAtK = float64(intersection) / float64(len(goldenTriples))
	}
	factF1 := harmonicMean(precisionAtK, recallAtK)

	// Step 4: Faithfulness — approximated as recall@k for P4
	// (full RubricScorer faithfulness wired in integration with nself-ai-gateway).
	// For recall eval, faithfulness is an independent metric; use recall@k as proxy in unit scope.
	faithfulness := recallAtK

	return RecallQualityResult{
		PrecisionAtK: precisionAtK,
		RecallAtK:    recallAtK,
		FactF1:       factF1,
		Faithfulness: faithfulness,
		K:            k,
		Retrieved:    retrievedTriples,
		Golden:       goldenTriples,
	}, nil
}

// tripleIntersectionCount counts how many triples in a are also in b.
// Comparison is exact (case-sensitive, no normalization).
func tripleIntersectionCount(a, b []Triple) int {
	set := make(map[Triple]struct{}, len(b))
	for _, t := range b {
		set[t] = struct{}{}
	}
	count := 0
	for _, t := range a {
		if _, ok := set[t]; ok {
			count++
		}
	}
	return count
}

// harmonicMean computes 2*p*r/(p+r) with zero-divide guard.
// Returns 0.0 when both p and r are 0.
func harmonicMean(p, r float64) float64 {
	if p+r == 0.0 {
		return 0.0
	}
	return 2.0 * p * r / (p + r)
}

// ensure math import used.
var _ = math.Sqrt
