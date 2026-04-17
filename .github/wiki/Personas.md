# Personas

**Status:** Active

## Overview

A persona is a configured AI identity inside ɳClaw. Each persona has a name, an avatar, a system prompt, behavior rules, a default model, and a memory scope. Switching personas swaps the active context — chat history, memory, and tool access change accordingly.

Personas let one ɳClaw install serve multiple use cases: a coding assistant, a personal journal, a research assistant, a customer-support bot. Each runs with its own brain.

The persona system is implemented in the `claw` plugin (server-side state) plus the Flutter app (selection UI, persona-scoped Riverpod providers).

## Requirements

| Item | Required | Notes |
|------|----------|-------|
| ɳSelf CLI | 1.0+ | F01-MASTER-VERSIONS |
| Plugin: `claw` | Yes | Pro tier — owns persona tables |
| Plugin: `ai` | Yes | Pro tier — runs the persona's model |
| Service: PostgreSQL | Yes | F08-SERVICE-INVENTORY |
| Tier | Pro ($1.99/mo) | per F07-PRICING-TIERS |
| Bundle | ɳClaw Bundle ($0.99/mo) | per F06-BUNDLE-INVENTORY |

## Configuration

Personas are configured via the app UI (Settings > Personas), not env vars. Per-persona settings:

| Setting | Default | Description |
|---------|---------|-------------|
| Name | (required) | Display name shown in sidebar / persona switcher |
| Avatar | (default icon) | Image displayed alongside the persona |
| System prompt | (empty) | Instructions appended to every conversation |
| Default model | account default | Override the global default model for this persona |
| Topic scope | unrestricted | Restrict memory to specific topics (ltree paths) |
| Tools | account default | Allow / deny specific tool plugins |

## Usage

### Creating a persona

Settings > Personas > New persona. Fill in name, avatar, system prompt, model, scope, tool allow-list. Save.

### Switching personas

Tap the persona avatar at the top of the sidebar. A switcher appears with all personas. Select one. The chat view, sidebar topics, and tool palette swap to match.

### Persona-scoped memory

Memory captured under persona A is not visible to persona B. This isolation is enforced by `claw` plugin — every memory write/read includes a `persona_id` filter. To share memory across personas, explicitly export and re-import (manual flow).

### Sharing personas

Personas can be shared across users on the same backend instance via Settings > Personas > Share. The recipient receives an invite; accepting copies the persona definition (system prompt, model, scope) into their own account. Shared persona memory remains private to each user.

## Limitations

- A persona's tool allow-list is enforced server-side; client-side UI may temporarily show a tool that the server rejects.
- Switching persona mid-conversation is supported but the AI may continue to reference the prior persona's context briefly until the next turn.
- Built-in personas (out-of-box defaults) are minimal. Most users define their own.
- Importing a shared persona does not import the original creator's memory — only the persona definition.

### Known issues

None currently tracked.

## Troubleshooting

### Persona switch doesn't persist after restart

**Symptom:** Selecting persona X, restarting the app, persona resets to the default.
**Cause:** Persona ID is not stored to `FlutterSecureStorage`, or the read on startup fails.
**Fix:** Verify settings are persisting (open Settings > Personas — does the create/edit save?). Check FlutterSecureStorage entitlement on macOS.

### Persona's memory bleeds into another persona

**Symptom:** Switching to persona B, the AI references content from persona A's conversations.
**Cause:** Memory query is missing the `persona_id` filter, or the `claw` plugin version is outdated.
**Fix:** Verify `claw` plugin is up-to-date (`nself plugin info claw`). File a bug if the issue persists in current versions.

### Tool not available for a persona

**Symptom:** AI says "I don't have access to tool X" even though X is installed.
**Cause:** The persona's tool allow-list excludes X.
**Fix:** Settings > Personas > edit persona > Tools > add X to the allow-list.

### Custom system prompt is ignored

**Symptom:** Set a custom system prompt for a persona but the AI ignores it.
**Cause:** `claw` plugin is using the global default prompt; persona prompts may need to be saved server-side.
**Fix:** Re-save the persona via Settings > Personas. Verify it's saved server-side via `claw` plugin REST: `GET /v1/plugins/claw/personas/<id>`.

## Related

- [[AI-Chat]] — the chat surface that personas drive
- [[Memory]] — persona-scoped memory
- [[Tool-Calls]] — per-persona tool allow-lists
- [[Architecture-Deep-Dive]] — persona data flow
- [[Features]] — full feature index

← [[Features]] | [[Home]] →
