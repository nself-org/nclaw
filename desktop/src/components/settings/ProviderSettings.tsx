// ɳClaw Desktop — Provider Settings section
import React, { useState } from "react";
import { useSettings, maskKey, type ProviderSettings as PS } from "../../lib/settings-store";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const PROVIDERS: { id: PS["id"]; label: string; requiresKey: boolean; defaultUrl: string }[] = [
  { id: "local-llamacpp", label: "Local (llama.cpp)", requiresKey: false, defaultUrl: "http://127.0.0.1:8080" },
  { id: "ollama-sidecar", label: "Ollama sidecar", requiresKey: false, defaultUrl: "http://127.0.0.1:11434" },
  { id: "openai", label: "OpenAI", requiresKey: true, defaultUrl: "https://api.openai.com/v1" },
  { id: "anthropic", label: "Anthropic", requiresKey: true, defaultUrl: "https://api.anthropic.com" },
  { id: "openrouter", label: "OpenRouter", requiresKey: true, defaultUrl: "https://openrouter.ai/api/v1" },
];

export function ProviderSettings(): React.ReactElement {
  const { settings, saveSection } = useSettings();
  const current = settings.provider;

  const [draft, setDraft] = useState({
    id: current.id,
    base_url: current.base_url,
    api_key_raw: "",
  });
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selected = PROVIDERS.find((p) => p.id === draft.id) ?? PROVIDERS[0];

  const handleProviderChange = (id: PS["id"]) => {
    const p = PROVIDERS.find((pp) => pp.id === id)!;
    setDraft({ id, base_url: p.defaultUrl, api_key_raw: "" });
    setSaved(false);
  };

  const handleSave = async () => {
    setError(null);
    try {
      const api_key_masked = draft.api_key_raw ? maskKey(draft.api_key_raw) : current.api_key_masked;
      await saveSection("provider", {
        id: draft.id,
        base_url: draft.base_url,
        api_key_masked,
      });
      setDraft((d) => ({ ...d, api_key_raw: "" }));
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <section aria-labelledby="provider-heading">
      <h2 id="provider-heading" className="text-lg font-semibold text-slate-100 mb-4">
        AI Provider
      </h2>

      {/* Provider selector */}
      <div className="mb-4">
        <Label htmlFor="provider-select" className="block text-sm font-medium text-slate-300 mb-1">
          Provider
        </Label>
        <Select value={draft.id} onValueChange={(v) => handleProviderChange(v as PS["id"])}>
          <SelectTrigger id="provider-select" aria-label="Select AI provider">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {PROVIDERS.map((p) => (
              <SelectItem key={p.id} value={p.id}>
                {p.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Base URL */}
      <div className="mb-4">
        <Label htmlFor="provider-base-url" className="block text-sm font-medium text-slate-300 mb-1">
          API Base URL
        </Label>
        <Input
          id="provider-base-url"
          type="url"
          value={draft.base_url}
          onChange={(e) => setDraft((d) => ({ ...d, base_url: e.target.value }))}
          placeholder={selected.defaultUrl}
          aria-label="API base URL"
        />
      </div>

      {/* API key */}
      {selected.requiresKey && (
        <div className="mb-4">
          <Label htmlFor="provider-api-key" className="block text-sm font-medium text-slate-300 mb-1">
            API Key
          </Label>
          <Input
            id="provider-api-key"
            type="password"
            value={draft.api_key_raw}
            onChange={(e) => setDraft((d) => ({ ...d, api_key_raw: e.target.value }))}
            placeholder={current.api_key_masked || "Enter API key"}
            autoComplete="off"
            aria-label="API key (masked)"
          />
          {current.api_key_masked && !draft.api_key_raw && (
            <p className="mt-1 text-xs text-slate-500">
              Saved key: <span className="font-mono">{current.api_key_masked}</span>
            </p>
          )}
        </div>
      )}

      {error && (
        <p role="alert" className="mb-3 text-sm text-red-400">
          {error}
        </p>
      )}

      <Button
        onClick={handleSave}
        aria-label="Save provider settings"
      >
        {saved ? "Saved" : "Save"}
      </Button>
    </section>
  );
}
