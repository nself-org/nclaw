// Package agenttools implements the nSelf backend management tool surface for nClaw agents.
//
// It exposes exactly 15 named tools across 3 authorization tiers as defined in
// the nClaw Memory / Agent / RAG Architecture Specification §9.
//
// Tier 1 — Read-only (5 tools, always available, no confirmation):
//   - NselfDbQuery   — SELECT-only SQL queries via nSelf admin API
//   - NselfApiGet    — Arbitrary authenticated GET to any nSelf endpoint
//   - NselfLogTail   — Tail recent log lines for a named service
//   - NselfMetricsGet — Retrieve a named metric over a time range
//   - NselfUserLookup — Search for users by query string
//
// Tier 2 — Write (6 tools, require confirmed=true in params):
//   - NselfApiPost         — POST/PATCH to any nSelf endpoint
//   - NselfUserUpdate      — Update a user record by ID
//   - NselfFeatureFlag     — Set or toggle a feature flag
//   - NselfNotificationSend — Send a notification to a user or group
//   - NselfPluginEnable    — Enable a plugin by slug
//   - NselfPluginDisable   — Disable a plugin by slug
//
// Tier 3 — Destructive (4 tools, require AUTHORIZE token in params["authorize_token"]):
//   - NselfMigrationRun — Run a database migration
//   - NselfDeploy       — Trigger a backend deployment
//   - NselfUserDelete   — Permanently delete a user and all their data (GDPR)
//   - NselfConfigSet    — Set a backend configuration key
//
// All Tier 2+ operations write an audit record to nclaw_user_memories
// (namespace="system/nclaw", memoryType="audit") BEFORE executing, so that
// failed operations are still logged.
//
// All HTTP calls go via the NCLAW_NSELF_API_URL environment variable.
// No URLs or IPs are hardcoded. Authentication uses NCLAW_NSELF_SERVICE_TOKEN.
//
// SPORT: P2-E5-W3-S6-T06 §9 backend tool surface.
package agenttools
