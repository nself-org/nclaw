# Local AI in ɳClaw

ɳClaw can run a language model directly on your device. No cloud, no API keys, no ongoing cost per message. You search for a model, download it once, and every conversation stays local.

---

## Finding a model

Open **Settings → Local AI**. The search box queries HuggingFace for GGUF-format models. Type a name (for example "Llama 3.2 3B" or "Qwen 2.5 1B") and press Search or Enter.

Results show the model name, download count, and number of GGUF variants. A higher download count usually means the model is well-tested.

---

## Picking a quantisation

Each GGUF model comes in multiple quantised variants. The file selector appears after you click a result. It defaults to `Q4_K_M`, which gives the best balance of size, speed, and quality for most hardware. The file size is shown alongside each option.

Common options:

| Quantisation | Size | Quality | Good for |
|---|---|---|---|
| `Q4_K_M` | ~2–5 GB | High | Default — works on 8 GB RAM |
| `Q8_0` | ~2× Q4 | Near-lossless | Plenty of RAM, best quality |
| `Q2_K` | ~½ Q4 | Reduced | Tight storage |

---

## Downloading and loading

Click **Download & Load** to start. ɳClaw:

1. Downloads the GGUF file to its local models directory.
2. Verifies the SHA-256 checksum.
3. Loads the model into memory.

The button shows the current state: **Downloading…** while the file transfers, then **Loading model…** while it initialises. Downloads resume automatically if interrupted.

---

## Tokens per second and time to first token

Once a model is active, the chat interface shows two metrics below each assistant response:

- **TPS** — tokens per second. How fast the model generates text. Typical range: 15–80 tok/s depending on hardware and model size.
- **TTFT** — time to first token in milliseconds. How long the model takes to start responding.

These update after every response. Use them to evaluate whether a model is fast enough for your workflow.

---

## Memory usage

The status bar shows current RAM (and GPU VRAM on supported hardware) consumed by the active model. If memory is low, ɳClaw warns before loading. Unloading a model frees memory immediately.

macOS reports unified memory. Linux reports system RAM and VRAM separately where NVML is available.

---

## Swapping models

Loading a new model automatically unloads the previous one. The swap is synchronous: the old model releases all memory before the new one initialises. Multiple consecutive swaps do not accumulate memory.

---

## The five device tiers

ɳClaw picks a default model for first-time users based on device capabilities:

| Tier | Hardware | Default model | Size | Speed |
|---|---|---|---|---|
| **T0** | iPhone 11/12, old Android | Qwen 2.5 0.5B | 350 MB | 15–30 tok/s |
| **T1** | iPhone 13/14, 8 GB laptop | Llama 3.2 1B | 700 MB | 20–40 tok/s |
| **T2** | M1/M2 Mac, iPhone 15/16, modern Windows | Llama 3.2 3B | 2 GB | 25–100 tok/s |
| **T3** | M1/M2 Pro, gaming PC, 16–32 GB workstation | Llama 3.1 8B | 4.5 GB | 30–80 tok/s |
| **T4** | M2/M3/M4 Max, 64 GB+ workstation | Qwen 2.5 14B or Llama 3.1 70B | 8–40 GB | 15–40 tok/s |

A 60-second benchmark on first run selects the tier. Monthly re-benchmarks adapt to changes in hardware or OS.

---

## Mobile power management

- **Low-power mode** drops one tier automatically.
- **Battery below 30%** disables local AI unless plugged in.
- **Plugged in** keeps local AI active regardless of battery.

Override under Settings → AI.

---

## Privacy

Local models run entirely on-device. Your conversations never leave your machine unless you enable Cloud Model Fallback in Settings → Privacy.

---

## Supported hardware

| Platform | Acceleration |
|---|---|
| macOS (Apple Silicon) | Metal (GPU layers configurable) |
| macOS (Intel) | CPU only |
| Linux | CUDA, Vulkan, or CPU |
| Windows | CUDA, Vulkan, or CPU |
| iOS / Android | CPU (coming) |

---

## See also

- [ADR-0009: Device-Aware Local LLM Defaults](adr/0009-device-aware-llm.md)
- [Full technical guide](https://docs.nself.org/nclaw/local-llm) at docs.nself.org
