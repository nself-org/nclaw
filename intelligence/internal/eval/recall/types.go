// Package recall provides the recall-quality eval runner for ɳClaw memory evaluation.
// Validates BGE-M3 + reranker retrieval quality against golden triple sets.
// OD-E4-01 Path A resolution: this runner ONLY operates on synthetic golden sets —
// real user memory is NEVER passed to the eval harness.
package recall

// Triple represents a subject-predicate-object fact triple.
// Purpose: Ground-truth unit for recall-quality evaluation; matched against retrieved facts.
// Inputs: from golden YAML files or nclaw_memory_facts columns.
// Outputs: compared set-wise for precision@k, recall@k, fact_f1 computation.
// Constraints: All three fields required and non-empty for valid triple comparison.
// NOTE: This type mirrors schema.GoldenMemory in nself-eval-gate.
// Per DRY mandate (spec §15 nclaw cross-repo contract), Triple is declared here and
// nself-eval-gate imports it. Shared type via go module replace if needed.
type Triple struct {
	Subject   string `json:"subject" yaml:"subject"`
	Predicate string `json:"predicate" yaml:"predicate"`
	Object    string `json:"object" yaml:"object"`
}

// MemoryFactRow represents a row from nclaw_memory_facts used in triple extraction.
// Purpose: Input type for ExtractTriples; maps DB columns to struct fields.
// Inputs: scanned from nclaw_memory_facts via pgx; columns: subject, predicate, object.
// Outputs: converted to []Triple for recall metric computation.
// Constraints: is_golden column marks synthetic eval facts; routine queries should never
// include real user memory in eval runs (OD-E4-01 constraint).
type MemoryFactRow struct {
	ID        string `json:"id" db:"id"`
	Subject   string `json:"subject" db:"subject"`
	Predicate string `json:"predicate" db:"predicate"`
	Object    string `json:"object" db:"object"`
	IsGolden  bool   `json:"is_golden" db:"is_golden"`
}

// RecallQualityResult holds all metrics from a single recall-quality eval run.
// Purpose: Complete output of RecallQualityEval.Run; logged to eval runs and surfaced in CLI.
// Inputs: computed by RecallQualityEval from retrieved triples and golden set.
// Outputs: embedded in EvalRun.Results JSONB; surfaced in nself ci eval output.
// Constraints: PrecisionAtK, RecallAtK, FactF1, Faithfulness all in [0,1].
//
//	Retrieved and Golden populated for debugging/inspection.
type RecallQualityResult struct {
	PrecisionAtK float64  `json:"precision_at_k"`
	RecallAtK    float64  `json:"recall_at_k"`
	FactF1       float64  `json:"fact_f1"`
	Faithfulness float64  `json:"faithfulness"`
	K            int      `json:"k"`
	Retrieved    []Triple `json:"retrieved"`
	Golden       []Triple `json:"golden"`
}
