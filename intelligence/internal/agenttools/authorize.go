// Package agenttools implements the nSelf backend tool surface for nClaw agents.
// Purpose: Provides 15 named tools across 3 authorization tiers (read-only, write,
//          destructive) for nClaw agent access to nSelf backend operations.
// Inputs:  Tool name, params map, optional confirmation bool or AUTHORIZE token.
// Outputs: Decoded API response or error describing the rejection/failure.
// Constraints: All ops go via NCLAW_NSELF_API_URL — no hardcoded IPs allowed.
//              Destructive ops require a well-formed AUTHORIZE token per deny-list pattern.
// SPORT:   §9 backend tool surface (P2-E5-W3-S6-T06).
package agenttools

import (
	"fmt"
	"strings"
)

// AuthorizeToken holds the parsed fields of a Tier 3 AUTHORIZE token.
// Format: "AUTHORIZE: <tool> reason: <text> consequence: <text>"
// Keys are case-insensitive; values are trimmed of leading/trailing whitespace.
type AuthorizeToken struct {
	ToolName    string
	Reason      string
	Consequence string
}

// ParseAuthorizeToken parses an AUTHORIZE token string into an AuthorizeToken.
// Expected format (case-insensitive keys, trimmed values):
//
//	"AUTHORIZE: NselfDeploy reason: fix prod bug consequence: rolling restart"
//
// Returns an error if:
//   - The string does not start with "AUTHORIZE:" (case-insensitive)
//   - "reason:" or "consequence:" keys are missing
//   - Any field value is empty after trimming
func ParseAuthorizeToken(raw string) (AuthorizeToken, error) {
	s := strings.TrimSpace(raw)

	// Case-insensitive prefix check for "AUTHORIZE:"
	lower := strings.ToLower(s)
	if !strings.HasPrefix(lower, "authorize:") {
		return AuthorizeToken{}, fmt.Errorf("authorize token must start with 'AUTHORIZE:'; got: %q", raw)
	}

	// Strip "AUTHORIZE:" prefix
	rest := strings.TrimSpace(s[len("authorize:"):])

	// Locate "reason:" (case-insensitive)
	reasonIdx := strings.Index(strings.ToLower(rest), "reason:")
	if reasonIdx < 0 {
		return AuthorizeToken{}, fmt.Errorf("authorize token missing 'reason:' field; got: %q", raw)
	}

	// Everything before "reason:" is the tool name
	toolName := strings.TrimSpace(rest[:reasonIdx])
	if toolName == "" {
		return AuthorizeToken{}, fmt.Errorf("authorize token has empty tool name; got: %q", raw)
	}

	// Everything after "reason:"
	afterReason := strings.TrimSpace(rest[reasonIdx+len("reason:"):])

	// Locate "consequence:" (case-insensitive)
	consIdx := strings.Index(strings.ToLower(afterReason), "consequence:")
	if consIdx < 0 {
		return AuthorizeToken{}, fmt.Errorf("authorize token missing 'consequence:' field; got: %q", raw)
	}

	reason := strings.TrimSpace(afterReason[:consIdx])
	if reason == "" {
		return AuthorizeToken{}, fmt.Errorf("authorize token has empty 'reason' value; got: %q", raw)
	}

	consequence := strings.TrimSpace(afterReason[consIdx+len("consequence:"):])
	if consequence == "" {
		return AuthorizeToken{}, fmt.Errorf("authorize token has empty 'consequence' value; got: %q", raw)
	}

	return AuthorizeToken{
		ToolName:    toolName,
		Reason:      reason,
		Consequence: consequence,
	}, nil
}

// validateAuthorizeToken parses the token and checks that ToolName matches
// the calling tool's expected name. Returns error if malformed or mismatched.
func validateAuthorizeToken(raw string, expectedToolName string) (AuthorizeToken, error) {
	tok, err := ParseAuthorizeToken(raw)
	if err != nil {
		return AuthorizeToken{}, err
	}
	if tok.ToolName != expectedToolName {
		return AuthorizeToken{}, fmt.Errorf(
			"authorize token tool name mismatch: got %q, expected %q",
			tok.ToolName, expectedToolName,
		)
	}
	return tok, nil
}
