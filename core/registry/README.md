# nClaw Model Registry

The model registry manages available LLM models for nClaw. This directory contains:

- **`models.toml`** — Canonical TOML registry of all bundled and available models
- **`maintainer-pubkey.pem`** — ed25519 public key for verifying signed models
- **`validate-model-registry`** — Cargo binary that validates schema and licenses

## Quick Reference

### Registry Schema

Models are TOML tables in `models.toml` with required fields:
- `id`: unique identifier
- `family`, `parameter_count`, `quant`: model metadata
- `gguf_hash`: SHA-256 for verification
- `size_mb`, `min_ram_mb`, `min_disk_mb`: hardware requirements
- `license`, `license_url`: license info
- `source_url`: download source
- `bundled_default_for_tier`: bundled tier or `null`
- `recommended_tier`: T0–T4
- `roles`: `["chat"]`, `["chat", "code"]`, etc.

### Adding a Model

See [Contributing: Adding a Model](../../.github/wiki/contributing/adding-a-model.md) for full walkthrough.

Quick: Add entry to `models.toml`, run validation, benchmark, submit PR.

### Validation

```bash
cd core && cargo run --bin validate-model-registry
```

Checks:
- Schema completeness
- License compatibility (GREEN / YELLOW / RED)
- GGUF hash format
- Tier and role consistency

## Architecture

The registry drives:
1. **Model bundling** — models in `bundled_default_for_tier` are shipped with the tier
2. **Device compatibility** — `recommended_tier` + `min_ram_mb` filters available models at runtime
3. **License enforcement** — download gates check license + user acceptance
4. **Version tracking** — `family` + version number enables model updates

## See Also

- [Full Contributing Guide](../../.github/wiki/contributing/adding-a-model.md)
- `models.toml` — live registry
- `maintainer-pubkey.pem` — signature verification key
