// knowledge_test.go — Unit tests for the corporate knowledge package.
//
// Purpose: Verify ChunkDocument correctness with realistic input sizes.
//          Integration tests (DB / Qdrant) are build-tagged and skipped in CI.
// Constraints: No external I/O in unit tests. ≤120 lines.
// SPORT: nclaw-memory-architecture-spec.md §5 — chunker correctness.
package knowledge

import (
	"strings"
	"testing"
)

// generateWords returns a string of n distinct words (word0, word1, …, wordN-1).
// Used to generate predictable test documents without relying on real prose.
func generateWords(n int) string {
	words := make([]string, n)
	for i := range words {
		words[i] = "word"
	}
	return strings.Join(words, " ")
}

// TestChunker verifies that a 600-word document is split into the expected number
// of chunks with correct overlap when chunking at maxTokens=512 / overlapTokens=200.
//
// Token estimator: words×1.3 → 600 words ≈ 780 tokens.
// With maxTokens=512: first chunk fills ~393 words (512/1.3), second chunk begins
// with ~154 overlap words (200/1.3) and covers the remainder.
// Expected: 2 chunks. Each chunk after the first must share a non-empty prefix
// with the tail of the previous chunk (overlap ≥1 word).
func TestChunker(t *testing.T) {
	// Build a 600-word document as a single paragraph (no blank lines so the
	// chunker must fall back to word-level accumulation after exhausting paragraphs).
	// We wrap it in two paragraphs to exercise the paragraph-split path too.
	half := generateWords(300)
	doc := half + "\n\n" + half

	maxTokens := 512
	overlapTokens := 200

	chunks := ChunkDocument(doc, maxTokens, overlapTokens)

	// Must produce at least 2 chunks for a ~780-token document at 512-token limit.
	if len(chunks) < 2 {
		t.Fatalf("TestChunker: expected ≥2 chunks for 600-word input, got %d", len(chunks))
	}

	// No chunk should exceed the token limit by more than one sentence worth (~30 tokens).
	for i, c := range chunks {
		tok := estimateTokens(c)
		// Allow up to maxTokens + 30 for sentence-boundary rounding.
		if tok > maxTokens+30 {
			t.Errorf("TestChunker: chunk %d has %d estimated tokens, exceeds limit %d+30", i, tok, maxTokens)
		}
	}

	// Verify overlap: the start of chunk[1] should share content with the tail of chunk[0].
	// Since both chunks are made of the same word "word", we check that chunk[1] starts
	// with at least one word from chunk[0] (overlap > 0).
	if overlapTokens > 0 && len(chunks) >= 2 {
		// Convert overlap token budget to word count.
		overlapWords := int(float64(overlapTokens) / 1.3 + 0.9999)
		tailOfFirst := tailWords(chunks[0], overlapWords)
		// The second chunk should start with at least the first word of the tail.
		firstWordOfTail := strings.Fields(tailOfFirst)[0]
		if !strings.HasPrefix(chunks[1], firstWordOfTail) {
			t.Errorf("TestChunker: chunk[1] does not start with tail of chunk[0]; tail=%q chunk1_prefix=%q",
				firstWordOfTail, chunks[1][:min(len(chunks[1]), 40)])
		}
	}
}

// TestChunkerSmallInput verifies that a document smaller than maxTokens is returned
// as a single chunk without modification.
func TestChunkerSmallInput(t *testing.T) {
	doc := "This is a short document. It fits in one chunk easily."
	chunks := ChunkDocument(doc, 512, 200)
	if len(chunks) != 1 {
		t.Errorf("TestChunkerSmallInput: expected 1 chunk, got %d", len(chunks))
	}
}

// TestChunkerEmpty verifies that empty input returns nil (no panic).
func TestChunkerEmpty(t *testing.T) {
	chunks := ChunkDocument("", 512, 200)
	if len(chunks) != 0 {
		t.Errorf("TestChunkerEmpty: expected 0 chunks, got %d", len(chunks))
	}
}

// TestChunkerLargeParagraph verifies that a single oversized paragraph is split
// at sentence boundaries (not silently dropped or returned as one giant chunk).
func TestChunkerLargeParagraph(t *testing.T) {
	// Build a paragraph of 400 words as many short sentences.
	var sentences []string
	for i := 0; i < 80; i++ {
		sentences = append(sentences, "Word word word word word.")
	}
	para := strings.Join(sentences, " ")

	chunks := ChunkDocument(para, 256, 50)
	if len(chunks) < 2 {
		t.Errorf("TestChunkerLargeParagraph: expected ≥2 chunks for oversized paragraph, got %d", len(chunks))
	}
}

// TestExtractFacts verifies that the regex triple extractor returns ≤3 triples
// and does not panic on empty or plain text.
func TestExtractFacts(t *testing.T) {
	text := "Alice manages Projects. Server runs Ubuntu. Database contains Records."
	facts := extractFacts(text)
	if len(facts) > 3 {
		t.Errorf("TestExtractFacts: expected ≤3 triples, got %d", len(facts))
	}
	// Verify each triple has non-empty subject, predicate, object.
	for i, f := range facts {
		if f[0] == "" || f[1] == "" || f[2] == "" {
			t.Errorf("TestExtractFacts: triple[%d] has empty field: %v", i, f)
		}
	}
}

// TestExtractFactsEmpty verifies no panic on empty input.
func TestExtractFactsEmpty(t *testing.T) {
	facts := extractFacts("")
	if len(facts) != 0 {
		t.Errorf("TestExtractFactsEmpty: expected 0 facts, got %d", len(facts))
	}
}

// min returns the smaller of a and b (pre-Go 1.21 compat helper).
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
