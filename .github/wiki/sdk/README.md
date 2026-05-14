# ɳClaw SDKs

Four language SDKs enable programmatic access to the ɳClaw API. Each SDK matches the CLI version (currently v1.1.1).

## Available SDKs

| Language | Path | Use case | Status |
|----------|------|----------|--------|
| **TypeScript** | `cli/sdk/ts/` | Web, Tauri desktop, Node.js backends | Available v1.1.1 |
| **Dart/Flutter** | `cli/sdk/flutter/` | Flutter mobile apps, desktop apps | Available v1.1.1 |
| **Go** | `cli/sdk/go/` | Server plugins, backend services, CLI tools | Available v1.1.1 |
| **Python** | `cli/sdk/py/` | Scripts, integrations, data pipelines | Available v1.1.1 |

## Quick start

See [SDK Usage Examples](usage.md) for TypeScript, Dart, Go, and Python code samples.

## Version alignment

All SDKs track the CLI version. When you update the CLI, update SDK references to the same version.

- CLI v1.1.1 → SDKs v1.1.1
- CLI v1.2.0 → SDKs v1.2.0 (future)

## Integration guide

- Web/desktop (TypeScript): `nclaw/desktop/package.json` imports `@nself/nclaw-sdk`
- Mobile (Flutter): `nclaw/mobile/pubspec.yaml` imports `nclaw_sdk`
- Plugins (Go): `plugins-pro/paid/*/go.mod` imports `github.com/nself-org/cli/sdk/go`
- Scripts (Python): install via `pip install nclaw-sdk` (v1.2.0+; currently in-tree)

## Status

SDK adoption is in progress (S11, P101). Internal use verified. Public release planned v1.2.0.
