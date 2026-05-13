# ADR-0011: Plugin Integration (Server-Side MCP-Style)

**Status:** Accepted 2026-05-11  
**Context:** ɳClaw integrates with email, calendar, browser, news, and other services via plugins.  
**Decision:** App calls server plugins over HTTPS using MCP-style protocol. No local plugin runtime in v1.1.1.  

## Context

ɳClaw's value compounds with integrations: email context, calendar events, web browsing history, budget data, etc. Plugins provide these integrations. Running plugins locally (in the app) would bloat the app and fragment implementation.

## Decision

v1.1.1 architecture:
- **Server-side plugins:** All plugins run on the user's self-hosted nSelf instance.
- **Remote procedure call:** App calls plugins over HTTPS to user's server, using an MCP-style RPC protocol.
- **No local plugin runtime:** Plugin code does not run in the app.
- **Deferred to v1.2.x:** Local plugin runtime (WASM-based) may ship in a future version if user demand is high.

v1.1.1 foundation: local LLM (offline-capable), sync engine, and credential vault.

## Rationale

- **Simpler app:** Smaller binary, fewer dependencies, easier to audit.
- **Server-side execution:** Plugins run where resources are plentiful; server can spawn background jobs.
- **User control:** Users self-host the nSelf instance; they control which plugins run and access to their data.
- **Faster iteration:** Plugin updates don't require app store review or user action.

## Consequences

**Positive:**
- App stays lean; plugins are opaque to app developers.
- Easy to add new plugins without app changes.

**Negative:**
- Plugin latency is network-dependent (200ms round-trip typical).
- App cannot run plugins offline (accepted for v1.1.1; future versions may embed WASM fallbacks).

## Alternatives Considered

- **Embedded local plugins (WASM):** Zero latency, full offline capability, but bloats app and requires plugin sandboxing.
- **Hybrid:** Server plugins + optional local WASM fallbacks. Complex; deferred.

## References

- MCP protocol: https://modelcontextprotocol.io/  
- nSelf plugins: https://docs.nself.org/plugins/  
- WASM: https://webassembly.org/
