// rrf.go — Reciprocal Rank Fusion over multiple ranked result lists.
//
// Purpose: Fuse N independently-ranked result lists (BM25, dense, graph) into
//          a single ranking using the RRF algorithm. RRF is rank-based so it is
//          robust to score-magnitude differences across retrieval paths.
// Inputs:  rankings [][]string — each inner slice is an ordered list of doc IDs
//          (rank 0 = most relevant). k float64 — Borda constant (60 per spec §6).
// Outputs: map[string]float64 — doc ID → RRF score (higher is better).
// Constraints: Pure function, no I/O, no external deps. ≤100 lines.
// SPORT: nclaw-memory-architecture-spec.md §6 — RRF k=60.
package memory

// RRFScore fuses N ranked lists of document IDs using Reciprocal Rank Fusion.
//
// Formula: score(d) += 1.0 / (k + float64(rank) + 1) for each list where d appears.
// rank is 0-indexed (first element = rank 0).
//
// A document that appears at rank 0 in all N lists achieves a maximum score.
// Documents absent from a list receive zero contribution from that list.
func RRFScore(rankings [][]string, k float64) map[string]float64 {
	if k <= 0 {
		k = 60.0
	}
	scores := make(map[string]float64)
	for _, list := range rankings {
		for rank, id := range list {
			if id == "" {
				continue
			}
			scores[id] += 1.0 / (k + float64(rank) + 1)
		}
	}
	return scores
}
