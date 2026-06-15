// chunker.go — Document chunking for the corporate knowledge ingest pipeline.
//
// Purpose: Split a raw text document into overlapping chunks of approximately
//          maxTokens tokens each, with overlapTokens carried forward from the
//          previous chunk. Uses a pure-Go word-count token estimator (no LLM call).
//          Split strategy: paragraph boundaries first; sentences if a paragraph
//          exceeds maxTokens; word-level fallback for pathological single sentences.
// Inputs:  text string, maxTokens int (default 512), overlapTokens int (default 200).
// Outputs: []string — ordered list of text chunks ready for embedding.
// Constraints: No I/O, no external deps. ≤150 lines. Token estimator: words×1.3.
// SPORT: nclaw-memory-architecture-spec.md §5 — chunking pipeline.
package knowledge

import (
	"strings"
	"unicode"
)

// estimateTokens returns an approximate token count for s using the word-count heuristic.
//
// Formula: len(strings.Fields(s)) * 1.3, rounded up to the nearest integer.
// This matches the BPE-style tokeniser average for English prose.
func estimateTokens(s string) int {
	words := len(strings.Fields(s))
	// multiply by 1.3 with ceiling
	return int(float64(words)*1.3 + 0.9999)
}

// tailWords returns the last n whitespace-separated words of s joined by a single space.
// Returns all of s if it has fewer than n words.
func tailWords(s string, n int) string {
	fields := strings.Fields(s)
	if len(fields) <= n {
		return s
	}
	return strings.Join(fields[len(fields)-n:], " ")
}

// splitBySentence breaks a paragraph into sentences using punctuation boundaries.
// Sentences are split after '.', '!', '?' that are followed by whitespace or end-of-string.
func splitBySentence(para string) []string {
	var sentences []string
	var buf strings.Builder
	runes := []rune(para)
	for i, r := range runes {
		buf.WriteRune(r)
		if (r == '.' || r == '!' || r == '?') && (i+1 >= len(runes) || unicode.IsSpace(runes[i+1])) {
			s := strings.TrimSpace(buf.String())
			if s != "" {
				sentences = append(sentences, s)
			}
			buf.Reset()
		}
	}
	if tail := strings.TrimSpace(buf.String()); tail != "" {
		sentences = append(sentences, tail)
	}
	return sentences
}

// ChunkDocument splits text into overlapping chunks of approximately maxTokens tokens.
//
// Algorithm:
//  1. Split by blank-line paragraph boundaries.
//  2. Accumulate paragraphs into a chunk; when adding the next paragraph would exceed
//     maxTokens, finalise the current chunk and start a new one.
//  3. If a single paragraph exceeds maxTokens, split it at sentence boundaries,
//     applying the same accumulation logic.
//  4. Each new chunk begins with the last overlapTokens worth of words from the
//     previous chunk to preserve context continuity.
//
// Callers should pass maxTokens=512, overlapTokens=200 per the architecture spec §5.
func ChunkDocument(text string, maxTokens int, overlapTokens int) []string {
	if maxTokens <= 0 {
		maxTokens = 512
	}
	if overlapTokens < 0 {
		overlapTokens = 0
	}
	// Derive an approximate word limit from the token target.
	// words = tokens / 1.3 (inverse of estimateTokens).
	overlapWords := int(float64(overlapTokens)/1.3 + 0.9999)

	// Split into paragraphs on blank lines.
	rawParas := strings.Split(text, "\n\n")
	var segments []string
	for _, p := range rawParas {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if estimateTokens(p) <= maxTokens {
			segments = append(segments, p)
		} else {
			// Paragraph too large — split at sentence boundaries.
			for _, s := range splitBySentence(p) {
				segments = append(segments, s)
			}
		}
	}

	if len(segments) == 0 {
		return nil
	}

	var chunks []string
	var prevChunkText string

	// addChunk finalises the current buffer as a new chunk and resets it.
	// Returns the recorded chunk text.
	addChunk := func(text string) {
		text = strings.TrimSpace(text)
		if text == "" {
			return
		}
		chunks = append(chunks, text)
		prevChunkText = text
	}

	// overlapPrefix builds the overlap prefix from the previous chunk, bounded so that
	// prefix+seg stays within maxTokens. overlapForSeg reduces the word budget when
	// the segment itself is large, preventing the combined chunk from overflowing.
	overlapPrefixForSeg := func(seg string) string {
		if prevChunkText == "" || overlapWords <= 0 {
			return ""
		}
		segTok := estimateTokens(seg)
		// Available token budget for overlap = maxTokens - segTok.
		// Convert back to words: availWords = (maxTokens - segTok) / 1.3.
		availBudgetTok := maxTokens - segTok
		if availBudgetTok <= 0 {
			return ""
		}
		availWords := int(float64(availBudgetTok)/1.3)
		if availWords <= 0 {
			return ""
		}
		budget := availWords
		if budget > overlapWords {
			budget = overlapWords
		}
		return tailWords(prevChunkText, budget) + " "
	}

	var buf strings.Builder

	flushBuf := func() {
		addChunk(buf.String())
		buf.Reset()
	}

	for _, seg := range segments {
		pending := strings.TrimSpace(buf.String())

		// Candidate: pending + seg.
		candidate := seg
		if pending != "" {
			candidate = pending + " " + seg
		}

		if estimateTokens(candidate) <= maxTokens {
			// Fits — accumulate.
			if pending != "" {
				buf.WriteString(" ")
			}
			buf.WriteString(seg)
			continue
		}

		// Does not fit. Flush current buffer first (if non-empty).
		if pending != "" {
			flushBuf()
		}

		// Now try adding seg to a fresh chunk (with bounded overlap prefix).
		prefix := overlapPrefixForSeg(seg)
		withOverlap := prefix + seg
		if estimateTokens(withOverlap) <= maxTokens {
			buf.WriteString(withOverlap)
			continue
		}

		// seg alone (even with bounded overlap) is too large — split it at sentence level.
		// This handles single paragraphs > maxTokens that weren't caught above.
		sentenceParts := splitBySentence(seg)
		if len(sentenceParts) == 0 {
			// Degenerate: emit the segment as-is (best effort).
			buf.WriteString(prefix)
			buf.WriteString(seg)
			flushBuf()
			continue
		}
		firstSentence := true
		for _, sp := range sentenceParts {
			pend := strings.TrimSpace(buf.String())
			cand := sp
			if pend != "" {
				cand = pend + " " + sp
			}
			if estimateTokens(cand) <= maxTokens {
				if pend != "" {
					buf.WriteString(" ")
				} else if firstSentence {
					buf.WriteString(overlapPrefixForSeg(sp))
				}
				buf.WriteString(sp)
			} else {
				if pend != "" {
					flushBuf()
				}
				buf.WriteString(overlapPrefixForSeg(sp))
				buf.WriteString(sp)
			}
			firstSentence = false
		}
	}
	flushBuf()

	return chunks
}
