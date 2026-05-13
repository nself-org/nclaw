# ADR-0009: Device-Aware Local LLM Defaults

**Status:** Accepted 2026-05-11  
**Context:** Local LLM performance varies wildly across devices (4GB Android phone vs M2 Max workstation).  
**Decision:** Auto-detect device capability at first run; select optimal model tier from T0–T4 matrix.  

## Context

Running local LLM with appropriate model size dramatically improves UX (no network latency, no cost per inference). But shipping one model doesn't work: Llama 3.2 3B on a 4GB phone is unusable; Llama 3.2 1B on M2 Max is wasteful.

## Decision

First-run flow:
1. Fingerprint device (OS, CPU, RAM, GPU, NPU, free disk).
2. Score → tier T0–T4.
3. Download default model for that tier.
4. Benchmark (60s warmup + 200-token completion).
5. Measure tokens/sec, p99 latency, peak RAM, thermal throttle.
6. If below target → auto-downgrade one tier and re-download.
7. If well above target → offer one-time upgrade prompt.
8. Cache selection in config. Re-benchmark monthly or on hardware change.

Tier matrix spans Android 4GB phones (T0) through M2 Max workstations (T4).

Users can manually override model or tier per role (chat, summarize, embed, code).

## Rationale

- **Auto-detection:** Users don't need to understand model sizes or hardware specs.
- **Tier matrix:** Covers 99% of device range with sane defaults.
- **Benchmarking:** Real-world measurement beats heuristics.
- **Monthly re-check:** Catches thermal issues, storage degradation, background process changes.

## Consequences

**Positive:**
- Works well across device spectrum without user configuration.
- Users get the best UX possible for their hardware.

**Negative:**
- First run takes time (download 2GB+ model, run benchmark).
- Benchmarking is noisy; outliers may select wrong tier (mitigated by one-time override prompt).

## Alternatives Considered

- **Single bundled model:** Simpler, but wrong for most devices.
- **Manual selection:** User burden; most users pick wrong tier.

## References

- Llama 3.2: https://github.com/meta-llama/llama-models  
- Qwen 2.5: https://github.com/QwenLM/Qwen2.5  
- llama.cpp quantization: https://github.com/ggerganov/llama.cpp
