// Purpose: Tier 3 (destructive) nSelf backend tools.
//          4 tools: NselfMigrationRun, NselfDeploy, NselfUserDelete, NselfConfigSet.
//          Each requires a valid AUTHORIZE token with ToolName matching the calling tool.
//          Cross-tool AUTHORIZE reuse is rejected (ToolName mismatch check).
//          Audit record is written BEFORE execution.
// Inputs:  ctx, params map, authorizeToken string, mem MemoryClient, userID, sourceAccountID.
// Outputs: any (decoded API response), error.
// Constraints: Never calls production IPs directly. All via NCLAW_NSELF_API_URL.
//              AUTHORIZE token format: "AUTHORIZE: <tool> reason: <text> consequence: <text>".
//              This enforces the destructive-deny-list pattern at the agent layer.
// SPORT:   §9 Tier 3 table (P2-E5-W3-S6-T06).
package agenttools

import (
	"context"
	"fmt"
	"net/url"

	"github.com/google/uuid"
)

// NselfMigrationRun runs a database migration.
// Params: "version" (string, optional), additional migration params.
// Endpoint: POST /v1/admin/migrate
// WHY AUTHORIZE: running migrations on a production database is irreversible if data is mutated.
func NselfMigrationRun(
	ctx context.Context,
	params map[string]any,
	authorizeToken string,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfMigrationRun"

	if _, err := validateAuthorizeToken(authorizeToken, toolName); err != nil {
		return nil, fmt.Errorf("%s: %w", toolName, err)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	body := map[string]any{}
	if version, ok := params["version"].(string); ok && version != "" {
		body["version"] = version
	}
	return nSelfPost(ctx, "/v1/admin/migrate", body)
}

// NselfDeploy triggers a deployment of the nSelf backend.
// Params: "env" (string, optional, e.g. "staging"), "image" (string, optional).
// Endpoint: POST /v1/admin/deploy
// WHY AUTHORIZE: deploying to production without explicit human sign-off is a critical deny-list item.
func NselfDeploy(
	ctx context.Context,
	params map[string]any,
	authorizeToken string,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfDeploy"

	if _, err := validateAuthorizeToken(authorizeToken, toolName); err != nil {
		return nil, fmt.Errorf("%s: %w", toolName, err)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	body := map[string]any{}
	if env, ok := params["env"].(string); ok && env != "" {
		body["env"] = env
	}
	if image, ok := params["image"].(string); ok && image != "" {
		body["image"] = image
	}
	return nSelfPost(ctx, "/v1/admin/deploy", body)
}

// NselfUserDelete permanently deletes a user and all their data.
// Params: "user_id" (string, required).
// Endpoint: DELETE /v1/admin/users/{user_id}
// WHY AUTHORIZE: user deletion is irreversible and triggers GDPR hard-delete across all stores.
func NselfUserDelete(
	ctx context.Context,
	params map[string]any,
	authorizeToken string,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfUserDelete"

	if _, err := validateAuthorizeToken(authorizeToken, toolName); err != nil {
		return nil, fmt.Errorf("%s: %w", toolName, err)
	}

	targetUserID, _ := params["user_id"].(string)
	if targetUserID == "" {
		return nil, fmt.Errorf("%s: 'user_id' param is required", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	path := fmt.Sprintf("/v1/admin/users/%s", url.PathEscape(targetUserID))
	return nSelfDelete(ctx, path)
}

// NselfConfigSet sets a configuration value in the nSelf backend.
// Params: "key" (string, required), "value" (string, required).
// Endpoint: POST /v1/admin/config
// WHY AUTHORIZE: config changes can affect all users and cannot easily be undone if incorrect.
func NselfConfigSet(
	ctx context.Context,
	params map[string]any,
	authorizeToken string,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfConfigSet"

	if _, err := validateAuthorizeToken(authorizeToken, toolName); err != nil {
		return nil, fmt.Errorf("%s: %w", toolName, err)
	}

	key, _ := params["key"].(string)
	if key == "" {
		return nil, fmt.Errorf("%s: 'key' param is required", toolName)
	}
	value, ok := params["value"]
	if !ok {
		return nil, fmt.Errorf("%s: 'value' param is required", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	body := map[string]any{
		"key":   key,
		"value": value,
	}
	return nSelfPost(ctx, "/v1/admin/config", body)
}
