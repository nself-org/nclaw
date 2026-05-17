// ɳClaw Desktop — LLM type definitions shared across hooks and components.

// ---------------------------------------------------------------------------
// HuggingFace search types (T01)
// ---------------------------------------------------------------------------

export interface HfGgufFile {
  filename: string;
  size_bytes: number | null;
  quant: string | null;
}

export interface HfModel {
  id: string;
  name: string;
  downloads: number;
  likes: number;
  gguf_files: HfGgufFile[];
}

// ---------------------------------------------------------------------------
// Download queue types (T02)
// ---------------------------------------------------------------------------

export type DownloadStatus =
  | "queued"
  | "downloading"
  | "verifying"
  | "done"
  | { failed: string }
  | "cancelled";

export interface DownloadEntry {
  id: string;
  url: string;
  filename: string;
  expected_sha256: string | null;
  status: DownloadStatus;
  bytes_received: number;
  total_bytes: number | null;
}

export interface DownloadProgress {
  id: string;
  status: DownloadStatus;
  bytes_received: number;
  total_bytes: number | null;
  bytes_per_sec: number;
}

// ---------------------------------------------------------------------------
// Model config types (T03)
// ---------------------------------------------------------------------------

export interface ModelConfig {
  /** Number of model layers offloaded to GPU. 0 = CPU-only. 999 = full offload. */
  n_gpu_layers: number;
  /** KV-cache context window size in tokens. */
  n_ctx: 512 | 1024 | 2048 | 4096 | 8192 | 16384 | 32768;
  /** Quantisation preference used when choosing a GGUF file to download. */
  quant: "Q4_K_M" | "Q5_K_M" | "Q8_0" | "F16" | "auto";
}

export const DEFAULT_MODEL_CONFIG: ModelConfig = {
  n_gpu_layers: 0,
  n_ctx: 4096,
  quant: "Q4_K_M",
};

// ---------------------------------------------------------------------------
// Stream metrics types (T04)
// ---------------------------------------------------------------------------

export interface StreamMetrics {
  /** Tokens per second (rolling). `null` before first token. */
  tps: number | null;
  /** Time-to-first-token in milliseconds. `null` before stream starts. */
  ttft_ms: number | null;
}

// ---------------------------------------------------------------------------
// Memory / VRAM telemetry types (T05)
// ---------------------------------------------------------------------------

export interface MemorySnapshot {
  gpu_used_mb: number;
  gpu_total_mb: number;
  ram_used_mb: number;
  ram_total_mb: number;
  source: string;
}
