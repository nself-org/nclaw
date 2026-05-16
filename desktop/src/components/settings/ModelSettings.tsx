// ɳClaw Desktop — Model Settings section
import React, { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge, type TierLevel } from "../tier-badge";
import { useSettings } from "../../lib/settings-store";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

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
    </section>
  );
}
