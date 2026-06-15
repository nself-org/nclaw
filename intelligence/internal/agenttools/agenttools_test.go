// Purpose: Unit tests for the agenttools package.
//          Covers: ParseAuthorizeToken (valid + 3 invalid cases) and
//          NselfDbQuery SELECT-only enforcement.
// SPORT:   P2-E5-W3-S6-T06 acceptance criteria tests.
package agenttools

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- TestParseAuthorizeToken ---

// TestParseAuthorizeToken_Valid verifies that a well-formed AUTHORIZE token parses correctly.
func TestParseAuthorizeToken_Valid(t *testing.T) {
	raw := "AUTHORIZE: NselfDeploy reason: fix prod bug consequence: rolling restart"
	tok, err := ParseAuthorizeToken(raw)
	require.NoError(t, err)
	assert.Equal(t, "NselfDeploy", tok.ToolName)
	assert.Equal(t, "fix prod bug", tok.Reason)
	assert.Equal(t, "rolling restart", tok.Consequence)
}

// TestParseAuthorizeToken_CaseInsensitiveKeys verifies that keys are case-insensitive.
func TestParseAuthorizeToken_CaseInsensitiveKeys(t *testing.T) {
	raw := "authorize: NselfMigrationRun REASON: db upgrade CONSEQUENCE: schema change"
	tok, err := ParseAuthorizeToken(raw)
	require.NoError(t, err)
	assert.Equal(t, "NselfMigrationRun", tok.ToolName)
	assert.Equal(t, "db upgrade", tok.Reason)
	assert.Equal(t, "schema change", tok.Consequence)
}

// TestParseAuthorizeToken_MissingReason verifies rejection when "reason:" is absent.
func TestParseAuthorizeToken_MissingReason(t *testing.T) {
	raw := "AUTHORIZE: NselfDeploy consequence: service restart"
	_, err := ParseAuthorizeToken(raw)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "reason")
}

// TestParseAuthorizeToken_MissingConsequence verifies rejection when "consequence:" is absent.
func TestParseAuthorizeToken_MissingConsequence(t *testing.T) {
	raw := "AUTHORIZE: NselfDeploy reason: need deploy"
	_, err := ParseAuthorizeToken(raw)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "consequence")
}

// TestParseAuthorizeToken_EmptyToolName verifies rejection when tool name is empty.
func TestParseAuthorizeToken_EmptyToolName(t *testing.T) {
	raw := "AUTHORIZE:  reason: something consequence: something else"
	_, err := ParseAuthorizeToken(raw)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "tool name")
}

// TestParseAuthorizeToken_MissingPrefix verifies rejection when AUTHORIZE: prefix is absent.
func TestParseAuthorizeToken_MissingPrefix(t *testing.T) {
	raw := "NselfDeploy reason: test consequence: none"
	_, err := ParseAuthorizeToken(raw)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "AUTHORIZE:")
}

// --- TestNselfDbQueryRejectsMutation ---

// TestNselfDbQueryRejectsMutation verifies that non-SELECT SQL is rejected.
func TestNselfDbQueryRejectsMutation(t *testing.T) {
	ctx := context.Background()

	cases := []struct {
		name string
		sql  string
	}{
		{"INSERT", "INSERT INTO users (name) VALUES ('evil')"},
		{"UPDATE", "UPDATE users SET admin=true WHERE 1=1"},
		{"DELETE", "DELETE FROM users"},
		{"DROP", "DROP TABLE users"},
		{"lowercase insert", "insert into users values (1)"},
		{"mixed case", "InSeRt INTO foo VALUES (1)"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := NselfDbQuery(ctx, map[string]any{"sql": tc.sql})
			require.Error(t, err, "expected error for non-SELECT SQL: %q", tc.sql)
			assert.Contains(t, err.Error(), "SELECT")
		})
	}
}

// TestNselfDbQueryAcceptsSelect verifies SELECT passes the guard (will fail HTTP without server).
func TestNselfDbQueryAcceptsSelect(t *testing.T) {
	// The SELECT guard must pass — the HTTP call will fail (no server), that's acceptable.
	ctx := context.Background()
	t.Setenv("NCLAW_NSELF_API_URL", "http://127.0.0.1:1")

	_, err := NselfDbQuery(ctx, map[string]any{"sql": "SELECT 1"})
	// May get a connection error — that's fine. Must NOT get a SELECT-rejection error.
	if err != nil {
		assert.NotContains(t, err.Error(), "only SELECT statements are allowed")
	}
}

// --- TestToolRegistry ---

// TestToolRegistryCount verifies exactly 15 tools are registered.
func TestToolRegistryCount(t *testing.T) {
	assert.Len(t, ToolRegistry, 15, "ToolRegistry must have exactly 15 entries")
}

// TestToolRegistryNames verifies all 15 expected tool names are present.
func TestToolRegistryNames(t *testing.T) {
	expected := []string{
		// Tier 1 (5)
		"NselfDbQuery", "NselfApiGet", "NselfLogTail", "NselfMetricsGet", "NselfUserLookup",
		// Tier 2 (6)
		"NselfApiPost", "NselfUserUpdate", "NselfFeatureFlag",
		"NselfNotificationSend", "NselfPluginEnable", "NselfPluginDisable",
		// Tier 3 (4)
		"NselfMigrationRun", "NselfDeploy", "NselfUserDelete", "NselfConfigSet",
	}
	for _, name := range expected {
		_, ok := ToolRegistry[name]
		assert.True(t, ok, "ToolRegistry missing tool: %q", name)
	}
}

// --- TestTier2RequiresConfirmed ---

// TestTier2RequiresConfirmed verifies Tier 2 tools reject calls without confirmed=true.
func TestTier2RequiresConfirmed(t *testing.T) {
	ctx := context.Background()
	ic := InvokeContext{}

	// No confirmed param
	_, err := NselfApiPost(ctx, map[string]any{"endpoint": "/v1/test"}, ic.Mem, ic.UserID, ic.SourceAccountID)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "confirmed")

	// confirmed=false
	_, err = NselfApiPost(ctx, map[string]any{
		"endpoint":  "/v1/test",
		"confirmed": false,
	}, ic.Mem, ic.UserID, ic.SourceAccountID)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "confirmed")
}

// --- TestTier3AuthorizeTokenMismatch ---

// TestTier3AuthorizeTokenMismatch verifies Tier 3 rejects AUTHORIZE with wrong tool name.
func TestTier3AuthorizeTokenMismatch(t *testing.T) {
	ctx := context.Background()
	ic := InvokeContext{}

	// Token says NselfMigrationRun but we call NselfDeploy
	wrongToken := "AUTHORIZE: NselfMigrationRun reason: test consequence: none"
	_, err := NselfDeploy(ctx, map[string]any{}, wrongToken, ic.Mem, ic.UserID, ic.SourceAccountID)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "tool name mismatch")
}

// TestTier3RejectsMissingToken verifies Tier 3 rejects empty AUTHORIZE token.
func TestTier3RejectsMissingToken(t *testing.T) {
	ctx := context.Background()
	ic := InvokeContext{}

	_, err := NselfDeploy(ctx, map[string]any{}, "", ic.Mem, ic.UserID, ic.SourceAccountID)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "AUTHORIZE:")
}
