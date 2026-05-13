# Contributing Models to nClaw

nClaw accepts contributions of new LLM models for bundled distribution. Contributors can propose models by submitting a pull request with registry updates and benchmark results.

## Quick Start

1. **Read the full guide:** [Adding a Model to nClaw Registry](../.github/wiki/contributing/adding-a-model.md)
2. **Add your model entry** to `nclaw/core/registry/models.toml` (TOML format)
3. **Run validation:** `cd core && cargo run --bin validate-model-registry`
4. **Benchmark on target hardware** — attach JSON results to PR
5. **Submit PR** with title `feat(registry): add <model-name>`

## Key Requirements

- **License:** GREEN tier (Apache-2.0, MIT, Llama Community, etc.) or approved YELLOW
- **Schema:** Valid TOML, passes `validate-model-registry` check
- **Hash:** SHA-256 of GGUF file, verified against public source
- **Benchmark:** Tokens/sec within 30% of recommended tier target
- **Roles:** Honest claim of supported roles (chat, code, summarize)

## Template

Copy this into `nclaw/core/registry/models.toml`:

```toml
[[model]]
id = "your-model-id"
family = "model-family"
parameter_count = "XB"
quant = "Q4_K_M"
gguf_hash = "sha256:YOUR_HASH_HERE"
size_mb = 2048
license = "MIT"
license_url = "https://..."
source_url = "https://..."
bundled_default_for_tier = "T2"
recommended_tier = "T2"
min_ram_mb = 4096
min_disk_mb = 6144
roles = ["chat"]
```

## Review SLA

Maintainer responds within **7 days**. Merge gates:
- License review
- Schema validation
- Hash verification
- Benchmark sanity check

## Need Help?

See the [full guide](../.github/wiki/contributing/adding-a-model.md) for detailed instructions, license compatibility, quantization guidance, and common questions.
