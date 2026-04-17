# Plugin Requirements

**Status:** Active

## Overview

ɳClaw is a consumer of pro plugins from the separate `plugins-pro/` repo. The plugins live server-side on a self-hosted ɳSelf backend and are installed via `nself plugin install`. This page lists which plugins are required, which are optional, and how they map to the ɳClaw bundle.

There is a deliberate naming overlap: this `claw/` repo is the client, while `plugins-pro/paid/claw/` is one of the required pro plugins. They are distinct things. When this page mentions "the `claw` plugin", it refers to the server-side plugin, not this client repo.

## Required pro plugins

The minimum set to run ɳClaw end-to-end. All three are mandatory.

| Plugin | Tier | Purpose | F04 row |
|--------|------|---------|---------|
| `ai` | Pro (max) | LLM gateway, provider routing, streaming | F04 |
| `claw` | Pro (max) | AI assistant core: memory, sessions, tool orchestration (NOT this client repo) | F04 |
| `mux` | Pro | Email pipeline, topic detection, content multiplexer | F04 |

Source of truth: `~/Sites/nself/.claude/docs/sport/F04-PLUGIN-INVENTORY-PRO.md`.

Without these three plugins, ɳClaw cannot send messages, retrieve memory, or detect topics.

## Optional ɳClaw-bundle plugins

The ɳClaw bundle covers all of the above plus a set of feature-add plugins. Per the bundle ($0.99/mo per F06), you get:

| Plugin | Tier | Adds |
|--------|------|------|
| `claw-web` | Pro (max) | Web client surface (separate web app served by the plugin) |
| `voice` | Pro (max) | Speech-to-text (Whisper) + text-to-speech |
| `browser` | Pro (max) | Browser automation tool (Chrome DevTools Protocol) |
| `google` | Pro | Gmail / Calendar / Drive integration |
| `notify` | Pro | Push notifications (FCM, APNs) |
| `cron` | Pro | Scheduled jobs / proactive triggers |
| `claw-budget` | Pro | Budget / spending intelligence (per F06) |
| `claw-news` | Pro | News digest / briefings (per F06) |

Bundle membership is canonical in `.claude/docs/sport/F06-BUNDLE-INVENTORY.md`.

## Tier and pricing

Per `.claude/docs/sport/F07-PRICING-TIERS.md` (locked 2026-03-23):

| Tier | Monthly | Annual | What ɳClaw can do |
|------|---------|--------|--------------------|
| Free | $0 | $0 | Cannot run — `ai` and `claw` are Pro-only |
| Basic | $0.99/mo | $9.99/yr | Cannot run — same reason |
| **Pro** | **$1.99/mo** | **$19.99/yr** | **Minimum viable: includes ai + claw + mux access** |
| Elite | $4.99/mo | $49.99/yr | Pro + email support |
| Business | $9.99/mo | $99.99/yr | Elite + 24h email + priority |
| Business+ | $49.99/mo | $499.99/yr | Business + dedicated channel |
| Enterprise | $99.99/mo | $999.99/yr | Business+ + managed DevOps |

Or:

| Bundle | Monthly | Annual | Includes |
|--------|---------|--------|----------|
| **ɳClaw Bundle** | **$0.99/mo** | (TBD) | All required + optional plugins above |
| ɳSelf+ | (N/A) | $49.99/yr | Everything: all bundles + all apps + priority support |

## Install sequence

License must be set BEFORE plugin install. The license is checked server-side at install time.

```bash
cd backend
nself license set $YOUR_KEY              # 1. license first
nself plugin install ai claw mux         # 2. required
nself plugin install claw-web voice browser google notify cron   # 3. optional bundle
nself build                              # 4. generate docker-compose
nself start                              # 5. start the stack
```

If a plugin install returns "license tier insufficient", the current key is below the required tier. Upgrade at [nself.org/pricing](https://nself.org/pricing).

## Verification

After install:

```bash
nself plugin list
```

Required plugins should appear with their version and tier. Then start the backend:

```bash
nself status
```

All services (postgres, hasura, auth, claw, ai, mux, plus any optional plugins) should report Healthy.

Test connectivity from the app:

- Run the Flutter app
- Complete onboarding (server URL, license key)
- Send a test message — streaming response confirms the full chain works

## Troubleshooting

### "License tier insufficient"

**Symptom:** `nself plugin install` returns this error.
**Cause:** The current license key is below the Pro tier (the `ai` and `claw` plugins are `max`/`Pro`).
**Fix:** Upgrade the key at [nself.org/pricing](https://nself.org/pricing). Run `nself license set $NEW_KEY`.

### Plugin "claw" missing after install

**Symptom:** `nself plugin list` shows ai and mux but not claw.
**Cause:** Common confusion: `claw` is the plugin (server-side, in `plugins-pro/`); the `claw/` repo is the client. They are different things.
**Fix:** Run `nself plugin install claw` explicitly. Or `nself plugin install ai claw mux` again to ensure all three.

### Optional bundle plugin not installed

**Symptom:** Need voice or browser tool; AI says "tool not available".
**Cause:** That bundle plugin is optional and was not installed.
**Fix:** `nself plugin install voice` (or `browser`, `google`, `notify`, `cron`, `claw-web`). Restart the backend.

## Related

- [[Getting-Started]] — full install walkthrough including license + plugins
- [[AI-Chat]] / [[Memory]] / [[Personas]] / [[Tool-Calls]] / [[E2E-Encryption]] — features and which plugins they need
- [[Architecture-Deep-Dive]] — how the plugins fit together
- [[Troubleshooting]] — license / install errors

← [[Home]] | [[Home]] →
