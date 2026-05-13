# Adding a Model to nClaw Registry

The nClaw registry enables contributors to add new LLM models for bundled distribution. This guide walks through the process from model selection to PR submission.

## Overview

nClaw uses a centralized TOML registry (`nclaw/core/registry/models.toml`) to manage available models. Each model entry specifies architecture, quantization, licensing, performance tiers, and download metadata. Contributors can propose new models by submitting a pull request with registry updates and benchmark results.

## Registry Schema

Model entries are TOML tables with the following required fields:

```toml
[[model]]
id = "llama-3.2-3b-instruct-q4_k_m"
family = "llama-3.2"
parameter_count = "3B"
quant = "Q4_K_M"
gguf_hash = "sha256:abc123..."
size_mb = 2048
license = "llama-3.2-community"
license_url = "https://www.llama.com/llama3_2/license/"
source_url = "https://huggingface.co/..."
bundled_default_for_tier = "T2"
recommended_tier = "T2"
min_ram_mb = 4096
min_disk_mb = 2500
roles = ["chat", "summarize"]
signature = "ed25519:..."  # optional, enables auto-pull
```

### Field Definitions

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | ✅ | Unique identifier; lowercase, alphanumeric + hyphen. Format: `<family>-<params>-<quant>` |
| `family` | string | ✅ | Model family (e.g., `llama-3.2`, `phi-3`, `mistral-7b`). Used for version tracking and updates. |
| `parameter_count` | string | ✅ | Number of parameters (e.g., `3B`, `7B`, `70B`). Must match model documentation. |
| `quant` | string | ✅ | Quantization format (`Q4_K_M`, `Q5_K_M`, `Q6_K`, `Q8_0`, `F16`, `F32`). |
| `gguf_hash` | string | ✅ | SHA-256 hash of the GGUF file. Computed via `sha256sum <file>`. |
| `size_mb` | integer | ✅ | Quantized model size in MB. Used for disk-space checks. |
| `license` | string | ✅ | SPDX identifier or custom license slug (e.g., `llama-3.2-community`, `MIT`, `Apache-2.0`). |
| `license_url` | string | ✅ | Canonical license text URL. |
| `source_url` | string | ✅ | Download source (e.g., Hugging Face, Ollama registry). Must be public and stable. |
| `bundled_default_for_tier` | string | ✅ | Performance tier this model is bundled as default for (`T0`, `T1`, `T2`, `T3`, `T4`). Or `null` if not bundled. |
| `recommended_tier` | string | ✅ | Recommended minimum tier for good UX (`T0`–`T4`). |
| `min_ram_mb` | integer | ✅ | Minimum RAM required to load (in MB). Measured at quantization used. |
| `min_disk_mb` | integer | ✅ | Minimum disk space (GGUF + 2× for temp). Set to `size_mb × 3`. |
| `roles` | array | ✅ | Supported roles: `["chat"]`, `["chat", "summarize"]`, `["chat", "code"]`, etc. |
| `signature` | string | ❌ | ed25519 signature from registry maintainer. Enables `--auto-pull` for users. Optional. |

## License Compatibility

Models must pass license review. GREEN / YELLOW / RED criteria:

### GREEN (Auto-approve)
- Llama Community License (LCL)
- Apache-2.0
- MIT
- Qwen License
- BSD-3-Clause

### YELLOW (Case-by-case review)
- Mistral Non-Commercial License (needs commercial carve-out or explicit approval)
- BigScience RAIL (restrictions on certain uses; review required)

### RED (Rejected)
- Any license restricting commercial use without a carve-out for nSelf users
- Proprietary or non-public licenses

## Quantization Guidance

Choose quantization based on recommended tier:

| Tier | RAM (GB) | Default | Alternative | Avoid |
|------|----------|---------|-------------|-------|
| T0 | 2–4 | Q4_K_M | Q3_K | F16, F32 |
| T1 | 4–8 | Q4_K_M | Q5_K_M (if space ok) | F32 |
| T2 | 8–16 | Q4_K_M | Q5_K_M | — |
| T3 | 16–32 | Q5_K_M | Q6_K | Q8_0 only for offline batch |
| T4 | 32+ | Q6_K | Q8_0 | F32 only if < 1B params |

**Why Q4_K_M is the default:** Best size-to-quality ratio. Tokens/second within 5% of F16 on modern hardware, at 1/4 the disk space.

## Hash and Signature

### Computing the Hash

```bash
wget https://huggingface.co/.../path/to/model.gguf
sha256sum model.gguf
# Output: abc123...  model.gguf
# Copy "abc123..." to the registry entry
```

### Signature (Optional, for Auto-Pull)

Registry maintainers can optionally sign models to enable zero-trust auto-pull:

```bash
# Maintainer signs the model file
echo -n "abc123..." | ed25519sum /path/to/model.gguf
# Output: ed25519:<sig>

# User can then auto-pull (no manual hash verification needed)
nClaw model pull llama-3.2-3b-instruct-q4_k_m --auto
```

Maintainer public key: `nclaw/core/registry/maintainer-pubkey.pem`

## Benchmark Requirements

Every new model must include benchmarks from at least one device per recommended tier. Benchmarks must measure **tokens per second** (inference throughput).

### Running Benchmarks

```bash
cd libs/libnclaw
cargo run --release --bin bench-model -- \
  --model-path /path/to/model.gguf \
  --device <device-type> \
  --prompt-length 128 \
  --completion-length 256 \
  --samples 5
```

Output: `bench-<device>-<model_id>.json`

### Expected Results

Benchmarks should show throughput **within 30% of tier target**:

| Tier | Target tok/s | Range |
|------|--------------|-------|
| T0 | 5–10 | 4–13 |
| T1 | 10–20 | 7–26 |
| T2 | 25–50 | 18–65 |
| T3 | 50–100 | 35–130 |
| T4 | 100+ | 70–150+ |

If results fall outside the range, re-evaluate the recommended tier.

## Pull Request Workflow

### Step 1: Fork the Repository

```bash
git clone https://github.com/nself-org/nclaw
cd nclaw
```

### Step 2: Add Registry Entry

Edit `nclaw/core/registry/models.toml`:

```toml
[[model]]
id = "phi-3-mini-4k-instruct-q4_k_m"
family = "phi-3"
parameter_count = "3.8B"
quant = "Q4_K_M"
gguf_hash = "sha256:def456789..."
size_mb = 1856
license = "MIT"
license_url = "https://huggingface.co/Microsoft/Phi-3-mini-4k-instruct"
source_url = "https://huggingface.co/Microsoft/Phi-3-mini-4k-instruct/blob/main/Phi-3-mini-4k-instruct-q4_k_m.gguf"
bundled_default_for_tier = "T2"
recommended_tier = "T2"
min_ram_mb = 4096
min_disk_mb = 5568
roles = ["chat", "code"]
```

### Step 3: Validate Registry

```bash
cd core && cargo run --bin validate-model-registry
```

Expected output:
```
Validating models.toml...
  phi-3-mini-4k-instruct-q4_k_m: License: GREEN, Schema: OK, Hash: verified ✓
  Summary: 1 model added, all valid
```

### Step 4: Attach Benchmarks

Include benchmark JSON files in the PR:
- `bench-m1-phi-3-mini.json` (macOS M1)
- `bench-linux-x86-phi-3-mini.json` (Linux x86-64)
- `bench-windows-gpu-phi-3-mini.json` (Windows with CUDA, if T3+)

### Step 5: Submit PR

Create pull request with:
- Title: `feat(registry): add Phi-3 Mini 4K Instruct Q4_K_M`
- Description:
  ```
  Adds Phi-3 Mini 4K Instruct Q4_K_M to bundled defaults for T2.
  
  - License: MIT (GREEN ✓)
  - Size: 1.8 GB quantized
  - Throughput: 32 tok/s on M1 (target 25–50)
  - Roles: chat, code
  
  Benchmarks attached:
  - bench-m1-phi-3-mini.json
  - bench-linux-x86-phi-3-mini.json
  ```

### Step 6: Review SLA

Maintainer responds within **7 days**. Merge gates:
1. ✅ License review: GREEN tier or approved YELLOW
2. ✅ Schema validation: passes `validate-model-registry`
3. ✅ Hash verified: GGUF SHA-256 matches source
4. ✅ Benchmark sanity: throughput within 30% of tier target
5. ✅ Role assumptions valid: claimed roles match model capabilities

## Common Questions

### Can I add a model with a custom license?

Submit it as YELLOW tier in the PR description. Include full license text and justification. The team will review and decide.

### What if my benchmark is slower than tier target?

Re-evaluate the `recommended_tier` and `bundled_default_for_tier`. A 3B model at 5 tok/s might be better as T1 than T2. Update the entry, re-benchmark, and submit.

### Can I update an existing model?

Yes — submit a PR with changes to the model entry (e.g., a new quantization or faster source URL). Increment the family version if it's a significant change (e.g., `llama-3.2-community` → `llama-3.2-v2-community`).

### How long does notarization/signing take?

Models added without a signature are valid. Signatures are optional for community contributions. Maintainers add signatures during the merge phase.

## Resources

- **Hugging Face GGUF Library:** https://huggingface.co/ggml-org/models
- **Ollama Model Library:** https://ollama.ai/library
- **SPDX License List:** https://spdx.org/licenses/
- **GGUF Spec:** https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
