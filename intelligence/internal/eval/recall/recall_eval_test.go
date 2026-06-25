package recall

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func mockRetrievalServer(t *testing.T, facts []retrievedFact) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(retrievalResponse{Facts: facts})
	}))
}

func TestRecallMetricsMathPerfect(t *testing.T) {
	// Retrieved = golden → precision@3=1.0, recall@3=1.0, fact_f1=1.0
	golden := []Triple{
		{Subject: "user", Predicate: "takes_medication", Object: "lisinopril"},
		{Subject: "user", Predicate: "takes_medication", Object: "metformin"},
		{Subject: "user", Predicate: "has_condition", Object: "hypertension"},
	}
	retrieved := []retrievedFact{
		{Subject: "user", Predicate: "takes_medication", Object: "lisinopril"},
		{Subject: "user", Predicate: "takes_medication", Object: "metformin"},
		{Subject: "user", Predicate: "has_condition", Object: "hypertension"},
	}
	srv := mockRetrievalServer(t, retrieved)
	defer srv.Close()

	eval := &RecallQualityEval{
		RetrievalURL: srv.URL,
		Timeout:      5 * time.Second,
		K:            3,
	}

	result, err := eval.Run(context.Background(), "medications", golden, 3)
	if err != nil {
		t.Fatalf("Run error: %v", err)
	}

	if !floatEq(result.PrecisionAtK, 1.0) {
		t.Errorf("expected precision@3=1.0, got %.4f", result.PrecisionAtK)
	}
	if !floatEq(result.RecallAtK, 1.0) {
		t.Errorf("expected recall@3=1.0, got %.4f", result.RecallAtK)
	}
	if !floatEq(result.FactF1, 1.0) {
		t.Errorf("expected fact_f1=1.0, got %.4f", result.FactF1)
	}
	if result.K != 3 {
		t.Errorf("expected K=3, got %d", result.K)
	}
}

func TestRecallMetricsPartialRetrieval(t *testing.T) {
	// 2 of 3 golden triples retrieved → precision@3=2/3, recall@3=2/3, fact_f1=2/3
	golden := []Triple{
		{Subject: "user", Predicate: "takes_medication", Object: "lisinopril"},
		{Subject: "user", Predicate: "takes_medication", Object: "metformin"},
		{Subject: "user", Predicate: "has_condition", Object: "hypertension"},
	}
	retrieved := []retrievedFact{
		{Subject: "user", Predicate: "takes_medication", Object: "lisinopril"},
		{Subject: "user", Predicate: "takes_medication", Object: "metformin"},
		{Subject: "user", Predicate: "unrelated", Object: "noise"},
	}
	srv := mockRetrievalServer(t, retrieved)
	defer srv.Close()

	eval := &RecallQualityEval{RetrievalURL: srv.URL, Timeout: 5 * time.Second, K: 3}
	result, err := eval.Run(context.Background(), "medications", golden, 3)
	if err != nil {
		t.Fatalf("Run error: %v", err)
	}

	expectedP := 2.0 / 3.0
	expectedR := 2.0 / 3.0
	expectedF1 := harmonicMean(expectedP, expectedR)

	if !floatEq(result.PrecisionAtK, expectedP) {
		t.Errorf("expected precision@3=%.4f, got %.4f", expectedP, result.PrecisionAtK)
	}
	if !floatEq(result.RecallAtK, expectedR) {
		t.Errorf("expected recall@3=%.4f, got %.4f", expectedR, result.RecallAtK)
	}
	if !floatEq(result.FactF1, expectedF1) {
		t.Errorf("expected fact_f1=%.4f, got %.4f", expectedF1, result.FactF1)
	}
}

func TestRecallZeroDivideGuardFactF1(t *testing.T) {
	// No overlap at all → precision@k=0, recall@k=0, fact_f1 must be 0.0 (not panic)
	golden := []Triple{
		{Subject: "user", Predicate: "takes_medication", Object: "lisinopril"},
	}
	retrieved := []retrievedFact{
		{Subject: "user", Predicate: "unrelated", Object: "noise"},
	}
	srv := mockRetrievalServer(t, retrieved)
	defer srv.Close()

	eval := &RecallQualityEval{RetrievalURL: srv.URL, Timeout: 5 * time.Second, K: 1}
	result, err := eval.Run(context.Background(), "medications", golden, 1)
	if err != nil {
		t.Fatalf("Run error: %v", err)
	}
	if result.FactF1 != 0.0 {
		t.Errorf("expected fact_f1=0.0 for zero P and R, got %.4f", result.FactF1)
	}
}

func TestRecallResultPopulatesDebugFields(t *testing.T) {
	golden := []Triple{
		{Subject: "user", Predicate: "likes", Object: "coffee"},
	}
	retrieved := []retrievedFact{
		{Subject: "user", Predicate: "likes", Object: "coffee"},
	}
	srv := mockRetrievalServer(t, retrieved)
	defer srv.Close()

	eval := &RecallQualityEval{RetrievalURL: srv.URL, Timeout: 5 * time.Second, K: 1}
	result, err := eval.Run(context.Background(), "preferences", golden, 1)
	if err != nil {
		t.Fatalf("Run error: %v", err)
	}
	if len(result.Retrieved) == 0 {
		t.Error("expected Retrieved field populated for debugging")
	}
	if len(result.Golden) == 0 {
		t.Error("expected Golden field populated for debugging")
	}
}

func syntheticGoldenFixture() []Triple {
	return []Triple{
		{Subject: "test_user", Predicate: "takes_medication", Object: "lisinopril"},
		{Subject: "test_user", Predicate: "takes_medication", Object: "metformin"},
		{Subject: "test_user", Predicate: "has_condition", Object: "hypertension"},
	}
}

func floatEq(a, b float64) bool {
	const eps = 0.0001
	diff := a - b
	if diff < 0 {
		diff = -diff
	}
	return diff < eps
}
