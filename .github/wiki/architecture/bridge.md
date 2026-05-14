# Bridge Routing Engine

The bridge decides, per prompt, where inference runs: local llama.cpp, a ServerMux relay, or a direct frontier API (Anthropic, OpenAI, Google). Decision #11.

## Pipeline

```
PromptRequest + BridgeContext
        │
        ▼
1. Per-conversation override?  ──yes──▶  apply immediately
        │ no
        ▼
2. Filter  — eliminate ineligible routes
   • Privacy::LocalOnly  → cloud routes removed
   • Offline             → cloud routes removed
   • Degraded            → DirectFrontier removed
   • No endpoint         → ServerMux removed
   • Cost exceeds budget → route removed
        │
        ▼
3. Score each candidate (0–100)
   Local:         base 50, +20 prefer_local, +10 Embed, -30 Code on T0/T1
   ServerMux:     base 60, +10 Online, -10 near budget
   DirectFrontier: base 40, +20 Code, -20 Default privacy
        │
        ▼
4. Pick — highest score
   Ties → lowest cost → lowest latency
        │
        ▼
   RouteDecision (Local | ServerMux | DirectFrontier | Queue)
```

## Types

| Type | Purpose |
|---|---|
| `PromptRequest` | Prompt metadata: tokens, class (Chat/Summarize/Code/Embed), privacy |
| `BridgeContext` | Runtime state: tier, connection, budgets, endpoints, policy |
| `RouteDecision` | Output: which backend + model hint |
| `RouteOverride` | Hard per-conversation override (ForceLocal / ForceServerMux / ForceFrontier) |
| `UserPolicy` | prefer_local flag, max cost/prompt, default provider |

## Default model hints

| Route | Model |
|---|---|
| Local | `registry::default_for_tier(local_tier)` |
| ServerMux | `"auto"` (server picks) |
| DirectFrontier anthropic | `claude-sonnet-4.6` |
| DirectFrontier openai | `gpt-4o-mini` |
| DirectFrontier google | `gemini-1.5-flash` |

Pure function — no I/O, no async. See `core/src/bridge/router.rs` and `core/tests/bridge_router_test.rs`.
