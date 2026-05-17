// ɳClaw Desktop — useModelConfig hook (T03)
//
// Reads and writes ModelConfig (n_gpu_layers, n_ctx, quant) through the
// settings store. The config is persisted via `set_setting` on save.

import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useState } from "react";
import type { ModelConfig } from "@/types/llm";
import { DEFAULT_MODEL_CONFIG } from "@/types/llm";

const SETTING_KEY = "llm_model_config";

export interface UseModelConfigReturn {
  /** Current model config (may be draft — not yet saved). */
  config: ModelConfig;
  /** True while loading initial config from backend. */
  loading: boolean;
  /** Update a single config field. Does not persist until `save()`. */
  patch: <K extends keyof ModelConfig>(key: K, value: ModelConfig[K]) => void;
  /** Persist current config to backend. */
  save: () => Promise<void>;
  /** True for 2 seconds after a successful save. */
  saved: boolean;
  /** Error message from the last failed save, or null. */
  error: string | null;
}

export function useModelConfig(): UseModelConfigReturn {
  const [config, setConfig] = useState<ModelConfig>(DEFAULT_MODEL_CONFIG);
  const [loading, setLoading] = useState(true);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    invoke<ModelConfig | null>("get_setting", { key: SETTING_KEY })
      .then((stored) => {
        if (stored) setConfig({ ...DEFAULT_MODEL_CONFIG, ...stored });
      })
      .catch(() => {
        // Key not yet set — use defaults.
      })
      .finally(() => setLoading(false));
  }, []);

  const patch = useCallback(
    <K extends keyof ModelConfig>(key: K, value: ModelConfig[K]) => {
      setConfig((prev) => ({ ...prev, [key]: value }));
    },
    []
  );

  const save = useCallback(async () => {
    setError(null);
    try {
      await invoke("set_setting", { key: SETTING_KEY, value: config });
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      setError(String(e));
    }
  }, [config]);

  return { config, loading, patch, save, saved, error };
}
