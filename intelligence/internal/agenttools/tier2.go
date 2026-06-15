// Purpose: Tier 2 (session-confirmed write) nSelf backend tools.
//          6 tools: NselfApiPost, NselfUserUpdate, NselfFeatureFlag,
//          NselfNotificationSend, NselfPluginEnable, NselfPluginDisable.
//          Each requires confirmed=true in params; returns error if !confirmed.
//          Audit record is written BEFORE execution (failed ops are still audited).
// Inputs:  ctx, params map, mem MemoryClient (may be nil), userID, sourceAccountID.
// Outputs: any (decoded API response), error.
// Constraints: No hardcoded URLs. All via NCLAW_NSELF_API_URL.
//              Audit BEFORE HTTP call (unconditional).
// SPORT:   §9 Tier 2 table (P2-E5-W3-S6-T06).
package agenttools

import (
	"context"
	"fmt"
	"net/url"

	"github.com/google/uuid"
)

// requireConfirmed checks the "confirmed" param and returns error if not true.
// WHY: Tier 2 tools mutate state — requiring explicit session confirmation prevents
//      accidental execution from ambiguous agent context.
func requireConfirmed(params map[string]any, toolName string) error {
	confirmed, ok := params["confirmed"]
	if !ok {
		return fmt.Errorf("%s: 'confirmed' param is required (must be true)", toolName)
	}
	switch v := confirmed.(type) {
	case bool:
		if !v {
			return fmt.Errorf("%s: 'confirmed' param must be true; got false", toolName)
		}
	default:
		return fmt.Errorf("%s: 'confirmed' param must be a boolean true; got %T", toolName, confirmed)
	}
	return nil
}

// NselfApiPost performs an authenticated POST (or PATCH) to a given nSelf endpoint.
// Params: "endpoint" (string, required), "body" (map, optional), "method" (string, "POST"/"PATCH"),
//         "confirmed" (bool, required true).
// Endpoint: POST/PATCH /v1/{endpoint}
func NselfApiPost(
	ctx context.Context,
	params map[string]any,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfApiPost"

	if err := requireConfirmed(params, toolName); err != nil {
		return nil, err
	}

	endpoint, _ := params["endpoint"].(string)
	if endpoint == "" {
		return nil, fmt.Errorf("%s: 'endpoint' param is required", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	var body map[string]any
	if b, ok := params["body"].(map[string]any); ok {
		body = b
	} else {
		body = map[string]any{}
	}

	method, _ := params["method"].(string)
	if method == "PATCH" {
		return nSelfPatch(ctx, endpoint, body)
	}
	return nSelfPost(ctx, endpoint, body)
}

// NselfUserUpdate updates a user record by ID.
// Params: "user_id" (string, required), "updates" (map, required), "confirmed" (bool, required true).
// Endpoint: PATCH /v1/admin/users/{user_id}
func NselfUserUpdate(
	ctx context.Context,
	params map[string]any,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfUserUpdate"

	if err := requireConfirmed(params, toolName); err != nil {
		return nil, err
	}

	targetUserID, _ := params["user_id"].(string)
	if targetUserID == "" {
		return nil, fmt.Errorf("%s: 'user_id' param is required", toolName)
	}

	updates, ok := params["updates"].(map[string]any)
	if !ok || len(updates) == 0 {
		return nil, fmt.Errorf("%s: 'updates' param is required and must be a non-empty map", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	path := fmt.Sprintf("/v1/admin/users/%s", url.PathEscape(targetUserID))
	return nSelfPatch(ctx, path, updates)
}

// NselfFeatureFlag sets or updates a feature flag.
// Params: "flag" (string, required), "enabled" (bool, required), "confirmed" (bool, required true).
// Endpoint: POST /v1/admin/flags
func NselfFeatureFlag(
	ctx context.Context,
	params map[string]any,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfFeatureFlag"

	if err := requireConfirmed(params, toolName); err != nil {
		return nil, err
	}

	flag, _ := params["flag"].(string)
	if flag == "" {
		return nil, fmt.Errorf("%s: 'flag' param is required", toolName)
	}

	enabled, ok := params["enabled"].(bool)
	if !ok {
		return nil, fmt.Errorf("%s: 'enabled' param must be a boolean", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	body := map[string]any{
		"flag":    flag,
		"enabled": enabled,
	}
	return nSelfPost(ctx, "/v1/admin/flags", body)
}

// NselfNotificationSend sends a notification to a user or group.
// Params: "recipient" (string, required), "message" (string, required),
//         "channel" (string, optional), "confirmed" (bool, required true).
// Endpoint: POST /v1/notify
func NselfNotificationSend(
	ctx context.Context,
	params map[string]any,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfNotificationSend"

	if err := requireConfirmed(params, toolName); err != nil {
		return nil, err
	}

	recipient, _ := params["recipient"].(string)
	if recipient == "" {
		return nil, fmt.Errorf("%s: 'recipient' param is required", toolName)
	}
	message, _ := params["message"].(string)
	if message == "" {
		return nil, fmt.Errorf("%s: 'message' param is required", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	body := map[string]any{
		"recipient": recipient,
		"message":   message,
	}
	if ch, ok := params["channel"].(string); ok && ch != "" {
		body["channel"] = ch
	}
	return nSelfPost(ctx, "/v1/notify", body)
}

// NselfPluginEnable enables a plugin by slug.
// Params: "slug" (string, required), "confirmed" (bool, required true).
// Endpoint: POST /v1/plugins/{slug}/enable
func NselfPluginEnable(
	ctx context.Context,
	params map[string]any,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfPluginEnable"

	if err := requireConfirmed(params, toolName); err != nil {
		return nil, err
	}

	slug, _ := params["slug"].(string)
	if slug == "" {
		return nil, fmt.Errorf("%s: 'slug' param is required", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	path := fmt.Sprintf("/v1/plugins/%s/enable", url.PathEscape(slug))
	return nSelfPost(ctx, path, map[string]any{})
}

// NselfPluginDisable disables a plugin by slug.
// Params: "slug" (string, required), "confirmed" (bool, required true).
// Endpoint: POST /v1/plugins/{slug}/disable
func NselfPluginDisable(
	ctx context.Context,
	params map[string]any,
	mem MemoryClient,
	userID uuid.UUID,
	sourceAccountID string,
) (any, error) {
	const toolName = "NselfPluginDisable"

	if err := requireConfirmed(params, toolName); err != nil {
		return nil, err
	}

	slug, _ := params["slug"].(string)
	if slug == "" {
		return nil, fmt.Errorf("%s: 'slug' param is required", toolName)
	}

	// Audit BEFORE execution.
	_ = WriteAuditRecord(ctx, mem, userID, sourceAccountID, toolName, params, "initiated")

	path := fmt.Sprintf("/v1/plugins/%s/disable", url.PathEscape(slug))
	return nSelfPost(ctx, path, map[string]any{})
}
