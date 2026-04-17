# Tool Calls

**Status:** Active

## Overview

Tool calls let the AI take actions in the world: search the web, read a file, run a shell command, control a browser, send an email, schedule a job. The AI requests a tool, the user approves (for sensitive tools), the tool runs, the result feeds back into the conversation.

ɳClaw orchestrates tool calls via the `claw` pro plugin, which dispatches to other plugins (browser, google, voice, mux, notify, cron) or to the local macOS daemon (file access, shell exec, screenshot, clipboard). Every tool call is recorded in an audit trail so the user can see what was done, when, and with what arguments.

## Requirements

| Item | Required | Notes |
|------|----------|-------|
| ɳSelf CLI | 1.0+ | F01-MASTER-VERSIONS |
| Plugin: `claw` | Yes | Pro tier — tool orchestration |
| Plugin: `ai` | Yes | Pro tier — tool calling support per model |
| Tool plugins | per tool | each tool requires its own plugin (see table below) |
| Service: PostgreSQL | Yes | F08-SERVICE-INVENTORY (audit table) |
| Tier | Pro ($1.99/mo) | per F07-PRICING-TIERS |
| Bundle | ɳClaw Bundle ($0.99/mo) | per F06-BUNDLE-INVENTORY (covers ai, claw + tool plugins) |

### Available tools (per F04-PLUGIN-INVENTORY-PRO)

| Tool | Plugin | Tier | Capability |
|------|--------|------|------------|
| Web search | `mux` | pro | search and retrieve web content |
| Browser automation | `browser` | max (Pro) | full browser control via CDP |
| Google services | `google` | pro | Gmail, Calendar, Drive |
| Voice (TTS / STT) | `voice` | max (Pro) | speech synthesis and recognition |
| Push notifications | `notify` | pro | send push to user devices |
| Scheduled jobs | `cron` | pro | schedule a future tool call |
| File access | macOS daemon | (no plugin) | read, write, list files (with user approval) |
| Shell execution | macOS daemon | (no plugin) | run commands (with user approval) |
| Screenshot | macOS daemon | (no plugin) | capture screen content |
| Clipboard | macOS daemon | (no plugin) | read or write clipboard |

For File / Shell / Screenshot / Clipboard, see [[Architecture-Deep-Dive]] for the local macOS menu-bar daemon (port 7710).

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `CLAW_TOOLS_REQUIRE_APPROVAL` | `true` for shell+file; `false` for read-only | Per-tool approval gate |
| `CLAW_TOOL_AUDIT_RETENTION_DAYS` | `90` | How long to keep tool-call audit records |
| `CLAW_MAX_TOOL_CHAIN_DEPTH` | `8` | Maximum chained tool calls per turn |

Per-tool env vars depend on the plugin (e.g., `BROWSER_HEADLESS=true` for `browser`).

## Usage

### How a tool call happens

1. AI generates a response containing a `tool_call(name, args)`.
2. ɳClaw inspects the tool. If approval is required (per `CLAW_TOOLS_REQUIRE_APPROVAL`), shows a dialog: "Allow ɳClaw to <action>?"
3. On approval, `claw` plugin dispatches to the relevant tool plugin or daemon.
4. The tool executes and returns a result.
5. Result is appended to context. AI continues from there. May chain another tool.
6. Final response streams back to the chat view.
7. The full tool call (name, args, result, approval status) is recorded in `np_claw_tool_audit`.

### Approving / denying tool calls

When a tool requires approval, ɳClaw shows a banner above the chat input:

> ɳClaw wants to run shell command: `ls ~/Documents`
> [Allow] [Deny] [Always allow this tool]

Choose Always allow only for tools you trust unconditionally.

### Viewing the tool audit trail

Settings > Tool History. Lists every tool call: timestamp, persona, tool name, arguments, result summary, approval state. Useful for reviewing what the AI has been doing on your behalf.

### Restricting tools per persona

Settings > Personas > edit > Tools tab. Allow / deny each tool. The AI will not see disabled tools in its tool list.

### Custom tool registration

Tools beyond the built-in plugins can be registered by writing a plugin that conforms to the `claw` tool protocol. See `plugins-pro/` documentation (out of scope for this wiki page).

## Limitations

- File / shell / screenshot / clipboard tools are macOS-only (require the menu-bar daemon at `desktop/`). On iOS / Android / Web, only plugin-based tools are available.
- The maximum tool-chain depth is 8 by default. AI can request more, but ɳClaw stops at the limit and surfaces the result so far.
- Browser automation requires the `browser` plugin to have a Chrome / Chromium instance available. Headless or attached.
- Tool calls are not encrypted end-to-end with the rest of the conversation. Tool args and results are visible to the backend (necessary because the backend executes them). Sensitive args should not rely on E2E.

### Known issues

None currently tracked.

## Troubleshooting

### Tool call hangs

**Symptom:** AI requests a tool, user approves, no result arrives.
**Cause:** Tool plugin not running or unreachable.
**Fix:** Check `nself plugin list` and `nself status`. Restart the relevant plugin: `nself restart browser`.

### Approval dialog doesn't appear

**Symptom:** AI silently runs a tool that should require approval.
**Cause:** `CLAW_TOOLS_REQUIRE_APPROVAL` is set to `false`, or the tool was previously marked Always allow.
**Fix:** Verify env var. Settings > Tool History > find the tool > revoke Always allow.

### "Tool not available"

**Symptom:** AI says "I don't have access to tool X".
**Cause:** Tool plugin not installed, or current persona's allow-list excludes the tool.
**Fix:** `nself plugin install <tool>` for the missing plugin. Settings > Personas > add tool to the persona's allow-list.

### File / shell tool fails on iOS / Android / Web

**Symptom:** AI tries to read a file or run a shell command on a non-macOS device; tool returns "not supported".
**Cause:** These tools are provided by the local macOS menu-bar daemon, which is macOS-only.
**Fix:** Use a different tool (e.g., AI can describe but not execute), or perform the action manually.

## Related

- [[AI-Chat]] — chat surface that drives tool calls
- [[Personas]] — per-persona tool allow-lists
- [[Architecture-Deep-Dive]] — tool dispatch flow
- [[Memory]] — tool results may be captured into memory
- [[Features]] — full feature index

← [[Features]] | [[Home]] →
