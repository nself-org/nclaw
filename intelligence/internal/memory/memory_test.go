// memory_test.go — Unit tests for RRF fusion and memory store helpers.
//
// Purpose: Verify RRFScore correctness and WriteMemory Postgres insert logic.
//          Integration tests (requiring live Qdrant/FalkorDB) are build-tagged
//          and skipped in CI unless NCLAW_QDRANT_URL is set.
// Constraints: Unit tests must pass without any external service.
//              Integration tests use //go:build integration tag.
package memory

import (
	"math"
	"testing"
)

// TestRRFScore_TwoRankings verifies the RRF formula with two known rankings.
//
// Expected: for k=60, doc-A at rank 0 in list-1 and rank 1 in list-2 should
// score higher than doc-B at rank 1 in list-1 and absent from list-2.
func TestRRFScore_TwoRankings(t *testing.T) {
	// Two rankings:
	// List 1: ["doc-A", "doc-B", "doc-C"]
	// List 2: ["doc-D", "doc-A"]
	rankings := [][]string{
		{"doc-A", "doc-B", "doc-C"},
		{"doc-D", "doc-A"},
	}
	scores := RRFScore(rankings, 60.0)

	// doc-A: rank 0 in list-1 → 1/(60+0+1) + rank 1 in list-2 → 1/(60+1+1)
	// = 1/61 + 1/62
	wantA := 1.0/61 + 1.0/62
	gotA := scores["doc-A"]
	if math.Abs(gotA-wantA) > 1e-9 {
		t.Errorf("doc-A score: want %.10f, got %.10f", wantA, gotA)
	}

	// doc-B: rank 1 in list-1 → 1/(60+1+1) = 1/62
	wantB := 1.0 / 62
	gotB := scores["doc-B"]
	if math.Abs(gotB-wantB) > 1e-9 {
		t.Errorf("doc-B score: want %.10f, got %.10f", wantB, gotB)
	}

	// doc-D: rank 0 in list-2 → 1/61
	wantD := 1.0 / 61
	gotD := scores["doc-D"]
	if math.Abs(gotD-wantD) > 1e-9 {
		t.Errorf("doc-D score: want %.10f, got %.10f", wantD, gotD)
	}

	// doc-A must score higher than doc-D (doc-A appears in both lists)
	if gotA <= gotD {
		t.Errorf("doc-A (%.10f) should outrank doc-D (%.10f)", gotA, gotD)
	}
}

// TestRRFScore_EmptyRankings verifies RRF handles empty input gracefully.
func TestRRFScore_EmptyRankings(t *testing.T) {
	scores := RRFScore(nil, 60.0)
	if len(scores) != 0 {
		t.Errorf("expected empty scores map for nil rankings, got %v", scores)
	}
	scores = RRFScore([][]string{}, 60.0)
	if len(scores) != 0 {
		t.Errorf("expected empty scores map for empty rankings, got %v", scores)
	}
}

// TestRRFScore_DefaultK verifies that k<=0 defaults to 60.
func TestRRFScore_DefaultK(t *testing.T) {
	rankings := [][]string{{"doc-X"}}
	// k=0 should fall back to 60.
	scoresK0 := RRFScore(rankings, 0)
	scoresK60 := RRFScore(rankings, 60)
	if scoresK0["doc-X"] != scoresK60["doc-X"] {
		t.Errorf("k=0 should default to k=60; k0=%.10f k60=%.10f", scoresK0["doc-X"], scoresK60["doc-X"])
	}
}

// TestRRFScore_Precision verifies scores match the formula to 4 decimal places.
func TestRRFScore_Precision(t *testing.T) {
	rankings := [][]string{
		{"alpha", "beta"},
		{"beta", "gamma"},
	}
	scores := RRFScore(rankings, 60.0)

	// beta: rank 1 in list-1 (1/62) + rank 0 in list-2 (1/61) = 1/62 + 1/61
	wantBeta := 1.0/62.0 + 1.0/61.0
	gotBeta := scores["beta"]
	// Verify to 4 decimal places.
	if math.Round(gotBeta*10000)/10000 != math.Round(wantBeta*10000)/10000 {
		t.Errorf("beta score precision: want %.4f, got %.4f", wantBeta, gotBeta)
	}
}

// TestExtractFacts_SimplePatterns verifies the regex-based fact extractor.
func TestExtractFacts_SimplePatterns(t *testing.T) {
	tests := []struct {
		input    string
		minFacts int
	}{
		{"Ali likes coffee. Ali works at Anthropic.", 2},
		{"", 0},
		{"No pattern here just free text", 0},
		{"System uses pgx", 1},
	}
	for _, tc := range tests {
		facts := extractFacts(tc.input)
		if len(facts) < tc.minFacts {
			t.Errorf("input %q: want at least %d facts, got %d", tc.input, tc.minFacts, len(facts))
		}
	}
}

// TestGraphQuery_NoURL verifies GraphQuery returns nil (not panic) when URL unset.
func TestGraphQuery_NoURL(t *testing.T) {
	t.Setenv("NCLAW_FALKORDB_URL", "")
	facts, err := GraphQuery(t.Context(), "some-user-id", 10)
	if err != nil {
		t.Fatalf("expected nil error when URL unset, got: %v", err)
	}
	if facts != nil {
		t.Errorf("expected nil facts when URL unset, got: %v", facts)
	}
}
