package recall

import (
	"testing"
)

func TestExtractTriplesBasic(t *testing.T) {
	rows := []MemoryFactRow{
		{ID: "1", Subject: "user", Predicate: "takes_medication", Object: "lisinopril", IsGolden: true},
		{ID: "2", Subject: "user", Predicate: "has_condition", Object: "hypertension", IsGolden: true},
	}
	triples := ExtractTriples(rows)
	if len(triples) != 2 {
		t.Errorf("expected 2 triples, got %d", len(triples))
	}
	if triples[0].Subject != "user" || triples[0].Predicate != "takes_medication" || triples[0].Object != "lisinopril" {
		t.Errorf("unexpected triple: %+v", triples[0])
	}
}

func TestExtractTriplesSkipsEmptyFields(t *testing.T) {
	rows := []MemoryFactRow{
		{ID: "1", Subject: "", Predicate: "takes_medication", Object: "lisinopril"},
		{ID: "2", Subject: "user", Predicate: "", Object: "lisinopril"},
		{ID: "3", Subject: "user", Predicate: "takes_medication", Object: ""},
		{ID: "4", Subject: "user", Predicate: "takes_medication", Object: "metformin"},
	}
	triples := ExtractTriples(rows)
	if len(triples) != 1 {
		t.Errorf("expected 1 valid triple (rows with empty fields skipped), got %d", len(triples))
	}
}

func TestExtractTriplesEmptyInput(t *testing.T) {
	triples := ExtractTriples([]MemoryFactRow{})
	if len(triples) != 0 {
		t.Errorf("expected 0 triples for empty input, got %d", len(triples))
	}
}
