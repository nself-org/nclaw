// ɳClaw Desktop — Model Settings section (T03: local-AI config controls added)
import React, { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge, type TierLevel } from "../tier-badge";
import { useSettings } from "../../lib/settings-store";
import { useModelConfig } from "@/hooks/useModelConfig";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { ModelConfig } from "@/types/llm";

interface ModelEntry {
  id: string;
  label: string;
  tier: TierLevel;
  is_default: boolean;
}

const ROLES: { key: "chat" | "summarizer" | "embedder" | "code"; label: string; description: string }[] = [
  { key: "chat", label: "Chat", description: "Primary conversational model" },
  { key: "summarizer", label: "Summarizer", description: "Used for context compression and topic labeling" },
  { key: "embedder", label: "Embedder", description: "Vector embeddings for memory search" },
  { key: "code", label: "Code", description: "Code generation and explanation" },
];

// ---------------------------------------------------------------------------
// Local-AI config sub-section (T03)
// ---------------------------------------------------------------------------

const CTX_OPTIONS: ModelConfig["n_ctx"][] = [512, 1024, 2048, 4096, 8192, 16384, 32768];
const QUANT_OPTIONS: { value: ModelConfig["quant"]; label: string }[] = [
  { value: "Q4_K_M", label: "Q4_K_M — balanced" },
  { value: "Q5_K_M", label: "Q5_K_M — quality+" },
  { value: "Q8_0", label: "Q8_0 — high quality" },
  { value: "F16", label: "F16 — full precision" },
  { value: "auto", label: "Auto — pick by tier" },
];

function LocalAiConfig(): React.ReactElement {
  const { config, loading, patch, save, saved: cfgSaved, error: cfgError } = useModelConfig();

  const handleGpuLayers = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = parseInt(e.target.value, 10);
    if (!Number.isNaN(v) && v >= 0 && v <= 999) {
      patch("n_gpu_layers", v);
    }
  };

  return (
    <section aria-labelledby="local-ai-heading" className="mt-8 pt-6 border-t border-slate-700">
      <h3
        id="local-ai-heading"
        className="text-base font-semibold text-slate-100 mb-4"
      >
        Local AI (llama.cpp)
      </h3>

      {loading ? (
        <p className="text-sm text-slate-500">Loading local AI config…</p>
      ) : (
        <div className="space-y-5">
          {/* GPU Layers */}
          <div>
            <Label htmlFor="gpu-layers" className="text-sm font-medium text-slate-300">
              GPU layers
            </Label>
            <p className="text-xs text-slate-500 mb-1">
              Number of model layers offloaded to GPU (0 = CPU only).
            </p>
            <Input
              id="gpu-layers"
              type="number"
              min={0}
              max={999}
              value={config.n_gpu_layers}
              onChange={handleGpuLayers}
              className="w-32"
              aria-label="GPU layers"
            />
          </div>

          {/* Context window */}
          <div>
            <Label htmlFor="n-ctx-select" className="text-sm font-medium text-slate-300">
              Context window
            </Label>
            <p className="text-xs text-slate-500 mb-1">
              Number of tokens held in context. Larger values use more memory.
            </p>
            <Select
              value={String(config.n_ctx)}
              onValueChange={(v) =>
                patch("n_ctx", parseInt(v, 10) as ModelConfig["n_ctx"])
              }
            >
              <SelectTrigger id="n-ctx-select" className="w-48" aria-label="Context window size">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {CTX_OPTIONS.map((opt) => (
                  <SelectItem key={opt} value={String(opt)}>
                    {opt.toLocaleString()} tokens
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Quantization */}
          <div>
            <Label htmlFor="quant-select" className="text-sm font-medium text-slate-300">
              Quantization (download preference)
            </Label>
            <p className="text-xs text-slate-500 mb-1">
              Preferred GGUF quant when searching and downloading models.
            </p>
            <Select
              value={config.quant}
              onValueChange={(v) => patch("quant", v as ModelConfig["quant"])}
            >
              <SelectTrigger id="quant-select" className="w-64" aria-label="Quantization preference">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {QUANT_OPTIONS.map(({ value, label }) => (
                  <SelectItem key={value} value={value}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      )}

      {cfgError && (
        <p role="alert" className="mt-3 text-sm text-red-400">
          {cfgError}
        </p>
      )}

      <Button
        onClick={save}
        disabled={loading}
        className="mt-4"
        aria-label="Save local AI config"
      >
        {cfgSaved ? "Saved" : "Save local AI config"}
      </Button>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function ModelSettings(): React.ReactElement {
  const { settings, saveSection } = useSettings();
  const [models, setModels] = useState<ModelEntry[]>([]);
  const [draft, setDraft] = useState(settings.model);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    invoke<ModelEntry[]>("list_models")
      .then((m) => setModels(m))
      .catch(() => setModels([]))
      .finally(() => setLoading(false));
  }, []);

  // Sync draft when store updates
  useEffect(() => {
    setDraft(settings.model);
  }, [settings.model]);

  const handleSave = async () => {
    setError(null);
    try {
      await saveSection("model", draft);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      setError(String(e));
    }
  };

  const selectedModel = (id: string) => models.find((m) => m.id === id);

  return (
    <section aria-labelledby="model-heading">
      <h2 id="model-heading" className="text-lg font-semibold text-slate-100 mb-4">
        Model Selection
      </h2>

      {loading ? (
        <p className="text-sm text-slate-500">Loading available models…</p>
      ) : (
        <div className="space-y-5">
          {ROLES.map((role) => {
            const chosen = selectedModel(draft[role.key]);
            return (
              <div key={role.key}>
                <div className="flex items-center justify-between mb-1">
                  <Label
                    htmlFor={`model-${role.key}`}
                    className="text-sm font-medium text-slate-300"
                  >
                    {role.label}
                  </Label>
                  {chosen && (
                    <TierBadge
                      tier={chosen.tier}
                      isOverride={!chosen.is_default}
                      className="ml-2"
                    />
                  )}
                </div>
                <p className="text-xs text-slate-500 mb-1">{role.description}</p>
                <Select
                  value={draft[role.key] || "__auto__"}
                  onValueChange={(v) => setDraft((d) => ({ ...d, [role.key]: v === "__auto__" ? "" : v }))}
                >
                  <SelectTrigger id={`model-${role.key}`} aria-label={`Select ${role.label} model`}>
                    <SelectValue placeholder="— Auto (device default) —" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__auto__">— Auto (device default) —</SelectItem>
                    {models.map((m) => (
                      <SelectItem key={m.id} value={m.id}>
                        {m.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            );
          })}
        </div>
      )}

      {error && (
        <p role="alert" className="mt-4 text-sm text-red-400">
          {error}
        </p>
      )}

      <Button
        onClick={handleSave}
        disabled={loading}
        className="mt-5"
        aria-label="Save model settings"
      >
        {saved ? "Saved" : "Save"}
      </Button>

      {/* T03 — local llama.cpp inference config */}
      <LocalAiConfig />
    </section>
  );
}
