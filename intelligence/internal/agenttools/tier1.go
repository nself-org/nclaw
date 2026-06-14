// Purpose: Tier 1 (always-available read-only) nSelf backend tools.
//          5 tools: NselfDbQuery, NselfApiGet, NselfLogTail, NselfMetricsGet, NselfUserLookup.
//          All are read-only. No confirmation or AUTHORIZE token required.
//          NselfDbQuery enforces SELECT-only (rejects INSERT/UPDATE/DELETE/DROP).
// Inputs:  ctx context.Context, params map[string]any
// Outputs: any (decoded JSON response body), error
// Constraints: All HTTP calls go via NCLAW_NSELF_API_URL env var — never hardcoded URLs.
//              Bearer token read from NCLAW_NSELF_SERVICE_TOKEN env var.
// SPORT:   §9 Tier 1 table (P2-E5-W3-S6-T06).
package agenttools

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
)

// nSelfGet performs an authenticated GET request to NCLAW_NSELF_API_URL + path.
// Returns the decoded JSON response or an error.
func nSelfGet(ctx context.Context, path string) (any, error) {
	baseURL := os.Getenv("NCLAW_NSELF_API_URL")
	if baseURL == "" {
		return nil, fmt.Errorf("NCLAW_NSELF_API_URL is not set")
	}
	token := os.Getenv("NCLAW_NSELF_SERVICE_TOKEN")

	fullURL := strings.TrimRight(baseURL, "/") + "/" + strings.TrimLeft(path, "/")

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fullURL, nil)
	if err != nil {
		return nil, fmt.Errorf("nself GET %s: build request: %w", path, err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("nself GET %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("nself GET %s: read body: %w", path, err)
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("nself GET %s: HTTP %d: %s", path, resp.StatusCode, string(body))
	}

	var result any
	if err := json.Unmarshal(body, &result); err != nil {
		// Return raw string if not JSON
		return string(body), nil
	}
	return result, nil
}

// nSelfPost performs an authenticated POST request to NCLAW_NSELF_API_URL + path with a JSON body.
func nSelfPost(ctx context.Context, path string, bodyMap map[string]any) (any, error) {
	baseURL := os.Getenv("NCLAW_NSELF_API_URL")
	if baseURL == "" {
		return nil, fmt.Errorf("NCLAW_NSELF_API_URL is not set")
	}
	token := os.Getenv("NCLAW_NSELF_SERVICE_TOKEN")

	fullURL := strings.TrimRight(baseURL, "/") + "/" + strings.TrimLeft(path, "/")

	bodyBytes, err := json.Marshal(bodyMap)
	if err != nil {
		return nil, fmt.Errorf("nself POST %s: marshal body: %w", path, err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fullURL, strings.NewReader(string(bodyBytes)))
	if err != nil {
		return nil, fmt.Errorf("nself POST %s: build request: %w", path, err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("nself POST %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("nself POST %s: read body: %w", path, err)
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("nself POST %s: HTTP %d: %s", path, resp.StatusCode, string(body))
	}

	var result any
	if err := json.Unmarshal(body, &result); err != nil {
		return string(body), nil
	}
	return result, nil
}

// nSelfPatch performs an authenticated PATCH request to NCLAW_NSELF_API_URL + path with a JSON body.
func nSelfPatch(ctx context.Context, path string, bodyMap map[string]any) (any, error) {
	baseURL := os.Getenv("NCLAW_NSELF_API_URL")
	if baseURL == "" {
		return nil, fmt.Errorf("NCLAW_NSELF_API_URL is not set")
	}
	token := os.Getenv("NCLAW_NSELF_SERVICE_TOKEN")

	fullURL := strings.TrimRight(baseURL, "/") + "/" + strings.TrimLeft(path, "/")

	bodyBytes, err := json.Marshal(bodyMap)
	if err != nil {
		return nil, fmt.Errorf("nself PATCH %s: marshal body: %w", path, err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, fullURL, strings.NewReader(string(bodyBytes)))
	if err != nil {
		return nil, fmt.Errorf("nself PATCH %s: build request: %w", path, err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("nself PATCH %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("nself PATCH %s: read body: %w", path, err)
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("nself PATCH %s: HTTP %d: %s", path, resp.StatusCode, string(body))
	}

	var result any
	if err := json.Unmarshal(body, &result); err != nil {
		return string(body), nil
	}
	return result, nil
}

// nSelfDelete performs an authenticated DELETE request to NCLAW_NSELF_API_URL + path.
func nSelfDelete(ctx context.Context, path string) (any, error) {
	baseURL := os.Getenv("NCLAW_NSELF_API_URL")
	if baseURL == "" {
		return nil, fmt.Errorf("NCLAW_NSELF_API_URL is not set")
	}
	token := os.Getenv("NCLAW_NSELF_SERVICE_TOKEN")

	fullURL := strings.TrimRight(baseURL, "/") + "/" + strings.TrimLeft(path, "/")

	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, fullURL, nil)
	if err != nil {
		return nil, fmt.Errorf("nself DELETE %s: build request: %w", path, err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("nself DELETE %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("nself DELETE %s: read body: %w", path, err)
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("nself DELETE %s: HTTP %d: %s", path, resp.StatusCode, string(body))
	}

	var result any
	if err := json.Unmarshal(body, &result); err != nil {
		return string(body), nil
	}
	return result, nil
}

// --- Tier 1 tools (5 read-only, no confirmation required) ---

// NselfDbQuery executes a SELECT-only query against the nSelf database.
// Params: "sql" (string, required, SELECT only), "args" ([]any, optional).
// Endpoint: POST /v1/admin/query {sql, args}
// WHY SELECT-only: prevents SQL injection and mutation of production data via the agent layer.
func NselfDbQuery(ctx context.Context, params map[string]any) (any, error) {
	sql, _ := params["sql"].(string)
	if sql == "" {
		return nil, fmt.Errorf("NselfDbQuery: 'sql' param is required")
	}

	// Reject non-SELECT statements (case-insensitive, trimmed)
	trimmed := strings.TrimSpace(strings.ToUpper(sql))
	if !strings.HasPrefix(trimmed, "SELECT") {
		return nil, fmt.Errorf("NselfDbQuery: only SELECT statements are allowed; got: %q", sql)
	}

	body := map[string]any{"sql": sql}
	if args, ok := params["args"]; ok {
		body["args"] = args
	}

	return nSelfPost(ctx, "/v1/admin/query", body)
}

// NselfApiGet performs a GET request to any nSelf API endpoint.
// Params: "endpoint" (string, required) — appended to NCLAW_NSELF_API_URL.
// Endpoint: GET /v1/{params["endpoint"]}
func NselfApiGet(ctx context.Context, params map[string]any) (any, error) {
	endpoint, _ := params["endpoint"].(string)
	if endpoint == "" {
		return nil, fmt.Errorf("NselfApiGet: 'endpoint' param is required")
	}
	return nSelfGet(ctx, endpoint)
}

// NselfLogTail retrieves the last N log lines for a named service.
// Params: "service" (string, required), "lines" (int, optional, default 100).
// Endpoint: GET /v1/admin/logs/{service}?lines={n}
func NselfLogTail(ctx context.Context, params map[string]any) (any, error) {
	service, _ := params["service"].(string)
	if service == "" {
		return nil, fmt.Errorf("NselfLogTail: 'service' param is required")
	}

	lines := "100"
	if n, ok := params["lines"]; ok {
		lines = fmt.Sprintf("%v", n)
	}

	path := fmt.Sprintf("/v1/admin/logs/%s?lines=%s",
		url.PathEscape(service), url.QueryEscape(lines))
	return nSelfGet(ctx, path)
}

// NselfMetricsGet retrieves a named metric over a given time range.
// Params: "metric" (string, required), "range" (string, optional, e.g. "1h").
// Endpoint: GET /v1/admin/metrics/{metric}?range={range}
func NselfMetricsGet(ctx context.Context, params map[string]any) (any, error) {
	metric, _ := params["metric"].(string)
	if metric == "" {
		return nil, fmt.Errorf("NselfMetricsGet: 'metric' param is required")
	}

	rangeVal := "1h"
	if r, ok := params["range"]; ok {
		rangeVal = fmt.Sprintf("%v", r)
	}

	path := fmt.Sprintf("/v1/admin/metrics/%s?range=%s",
		url.PathEscape(metric), url.QueryEscape(rangeVal))
	return nSelfGet(ctx, path)
}

// NselfUserLookup searches for users by query string.
// Params: "query" (string, required).
// Endpoint: GET /v1/admin/users/search?q={query}
func NselfUserLookup(ctx context.Context, params map[string]any) (any, error) {
	q, _ := params["query"].(string)
	if q == "" {
		return nil, fmt.Errorf("NselfUserLookup: 'query' param is required")
	}

	path := fmt.Sprintf("/v1/admin/users/search?q=%s", url.QueryEscape(q))
	return nSelfGet(ctx, path)
}
