package recall

// ExtractTriples converts nclaw_memory_facts rows to Triple slice.
// Purpose: Map DB fact rows to the canonical Triple type for set-comparison in recall metrics.
// Inputs: rows — slice of MemoryFactRow from nclaw_memory_facts.
// Outputs: []Triple with Subject, Predicate, Object populated; empty rows skipped.
// Constraints: Rows with any empty field are skipped (invalid triples).
//
//	OD-E4-01: only golden-set rows (is_golden=true) should be passed from eval runners.
func ExtractTriples(rows []MemoryFactRow) []Triple {
	triples := make([]Triple, 0, len(rows))
	for _, row := range rows {
		if row.Subject == "" || row.Predicate == "" || row.Object == "" {
			continue
		}
		triples = append(triples, Triple{
			Subject:   row.Subject,
			Predicate: row.Predicate,
			Object:    row.Object,
		})
	}
	return triples
}
