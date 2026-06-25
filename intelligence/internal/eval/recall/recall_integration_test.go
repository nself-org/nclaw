//go:build integration

package recall

import (
	"context"
	"testing"
	"time"
)

// TestGoldenSetRegressionFactF1 runs against a live plugin-retrieval instance.
// Purpose: Assert that BGE-M3 reranker quality has not regressed on the synthetic golden fixture.
// FAILURE = BGE-M3 reranker regression detected; MUST NOT be silenced.
// Requires: plugin-retrieval running at localhost:3771; golden facts seeded in nclaw_memory_facts.
// Build tag: integration — run with `go test -tags=integration ./...`
func TestGoldenSetRegressionFactF1(t *testing.T) {
	golden := syntheticGoldenFixture()
	eval := &RecallQualityEval{
		RetrievalURL: "http://localhost:3771/retrieve",
		Timeout:      30 * time.Second,
		K:            3,
	}

	result, err := eval.Run(context.Background(), "medications", golden, 3)
	if err != nil {
		t.Fatalf("RecallQualityEval.Run error: %v", err)
	}

	const minFactF1 = 0.80
	if result.FactF1 < minFactF1 {
		t.Errorf("REGRESSION DETECTED: fact_f1=%.4f < threshold %.2f — BGE-M3 reranker quality degraded",
			result.FactF1, minFactF1)
	}
}
