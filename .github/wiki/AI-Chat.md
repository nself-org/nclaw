# AI Chat

**Status:** Active

## Overview

AI Chat is the core conversational surface of ɳClaw. The user sends messages; the AI responds in streaming chunks; the conversation persists across sessions; tools can be invoked; context is managed automatically.

ɳClaw delegates the AI work to the `ai` and `claw` pro plugins on the user's nSelf backend. The `ai` plugin handles model routing and streaming. The `claw` plugin handles session state, tool orchestration, and memory injection. The Flutter client renders streaming markdown, captures input (text, voice, attachments), and surfaces tool-call approvals.

## Requirements

| Item | Required | Notes |
|------|----------|-------|
| ɳSelf CLI | 1.0+ | F01-MASTER-VERSIONS |
| Plugin: `ai` | Yes | Pro tier — see plugins-pro wiki |
| Plugin: `claw` | Yes | Pro tier — see plugins-pro wiki |
| Plugin: `mux` | Yes | Pro tier (for topic / context) |
| Service: PostgreSQL | Yes | F08-SERVICE-INVENTORY |
| Service: Redis | Yes | F08 (session + streaming cache) |
| Tier | Pro ($1.99/mo) | per F07-PRICING-TIERS |
| Bundle | ɳClaw Bundle ($0.99/mo) | per F06-BUNDLE-INVENTORY |

External services:

- An LLM provider key (Anthropic Claude, OpenAI, or any provider supported by the `ai` plugin) configured server-side.

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `AI_DEFAULT_MODEL` | (per ai plugin) | Default model for new conversations |
| `AI_PROVIDER_KEYS` | (none) | Per-provider API keys (Anthropic, OpenAI, etc.) |
| `CLAW_CONTEXT_WINDOW` | per-model max | Max tokens of context to send to the model |
| `CLAW_STREAM_ENABLED` | `true` | Stream responses chunk-by-chunk vs send full response |

## Usage

### Sending a message

Type into the input field and press Enter (or tap Send). The response streams back chunk-by-chunk as the model generates it. Markdown rendering, code highlighting, and link rendering happen on the fly.

### Continuing a conversation

Each conversation persists in the backend. Reopen ɳClaw at any time and pick up where you left off. The sidebar shows your conversations grouped by auto-detected topic (see [[Memory]]).

### Editing or regenerating a message

Long-press (mobile) or right-click (desktop) on any message:

- **Edit** — change the text and re-send. The AI re-generates from that point.
- **Regenerate** — re-run the same prompt with a different model output.
- **Branch** — fork the conversation into a new thread from this message.

### Attaching files or images

Tap the paperclip icon. Select a file or photo. ɳClaw uploads it via MinIO (S3-compatible) and includes a reference in the prompt. The AI describes images, reads PDFs, and reasons about code files.

### Voice input

Tap the microphone. Speak. Continuous mode listens until you stop, with silence detection. The transcription appears in the input field. Press Send. See [[Voice]] (planned wiki page) for details.

## Limitations

- Streaming requires a stable WebSocket connection (Hasura GraphQL subscriptions). On flaky networks, ɳClaw falls back to polling.
- Context window is bounded by the chosen model. ɳClaw automatically summarizes older turns when nearing the limit; some detail is lost.
- Multiple simultaneous chat tabs against the same JWT can hit Hasura subscription limits.
- Web build cannot use libnclaw FFI for E2E encryption. Use WASM stub or accept REST fallback.

### Known issues

None currently tracked.

## Troubleshooting

### Response doesn't stream — full message appears at once

**Symptom:** Send a message, wait, the full response arrives all at once instead of streaming.
**Cause:** `CLAW_STREAM_ENABLED` is set to `false`, or the WebSocket subscription is failing.
**Fix:** Verify `CLAW_STREAM_ENABLED=true` in backend env. Check browser DevTools / app logs for WSS errors.

### "Model not found"

**Symptom:** Sending a message returns "Model X not configured".
**Cause:** The selected model is not enabled in the `ai` plugin config (provider key missing).
**Fix:** Add the provider key to `AI_PROVIDER_KEYS` in the backend env. Restart the `ai` plugin: `nself restart ai`.

### "Context window exceeded"

**Symptom:** Long conversations start failing with a token-limit error.
**Cause:** Context exceeded the chosen model's window and auto-summarization is disabled or failing.
**Fix:** Verify `CLAW_CONTEXT_WINDOW` is set to a reasonable fraction of the model max (e.g., 80%). Branch the conversation to start fresh from the relevant turn.

### Tool call hangs

**Symptom:** AI requests a tool, the user approves, but the tool never returns.
**Cause:** The tool's plugin is missing or the tool endpoint is unreachable.
**Fix:** Check the `claw` plugin logs (`docker logs nself-claw`). Verify the relevant plugin (`browser`, `google`, `voice`) is installed and running.

## Related

- [[Memory]] — how chat context is captured and retrieved
- [[Personas]] — per-persona AI behavior
- [[Tool-Calls]] — function calling and tool execution
- [[E2E-Encryption]] — end-to-end encryption for chat content
- [[Architecture-Deep-Dive]] — full data flow
- [[Features]] — full feature index

← [[Features]] | [[Home]] →
