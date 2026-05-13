# How Local AI Works

ɳClaw runs a small AI model on your device — no cloud, no submissions. The model is picked automatically for your hardware the first time you run the app.

## The Five Tiers

| Tier | Hardware | Model | Size | Speed |
|------|----------|-------|------|-------|
| **T0** | iPhone 11/12, old Android | Qwen 2.5 0.5B | 350 MB | 15–30 tok/s |
| **T1** | iPhone 13/14, 8GB laptop | Llama 3.2 1B | 700 MB | 20–40 tok/s |
| **T2** | M1/M2 Mac, iPhone 15/16, modern Windows | Llama 3.2 3B | 2 GB | 25–50 tok/s (60–100 on Apple Silicon) |
| **T3** | M1/M2 Pro, gaming PC, 16–32GB workstation | Llama 3.1 8B | 4.5 GB | 30–80 tok/s |
| **T4** | M2/M3/M4 Max/Ultra, 64GB+ workstation | Qwen 2.5 14B or Llama 3.1 70B | 8–40 GB | 15–40 tok/s (opt-in) |

## First-Run Benchmark

When you open ɳClaw for the first time, a 60-second background benchmark measures your device:

- Tokens per second
- Peak RAM usage
- Thermal throttling
- Battery draw

If your device scores lower than expected for your tier, ɳClaw drops down one tier automatically. Monthly re-benchmarks adapt to OS updates or new apps.

## Mobile Power Management

- **Low-power mode** → drops one tier
- **Battery <30%** → disables local AI unless plugged in
- **Plugged in** → stays local

Override in Settings → AI if you want local AI when battery is low.

## Privacy

Local models run entirely on-device. Your conversations never leave your phone unless you explicitly enable Cloud Model Fallback in Settings → Privacy.

## Override Your Model

Settings → AI → Model Selection. Pick a different tier or import a custom GGUF file.

## See Also

- [Detailed Guide (web/docs)](../../web/docs/src/content/nclaw/local-ai.mdx) — full technical explanation
- [Marketing Overview (web/nclaw)](../../web/nclaw/src/content/local-ai.mdx) — friendly summary
