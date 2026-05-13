// Local AI Settings panel — tier override, benchmark history, installed models, custom GGUF import.
// Tauri commands defined in src-tauri/src/commands/local_ai.rs (stubs; wired in S15.T17).
import React, { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge, TierLevel } from "../../components/tier-badge";

// --- Types (mirror commands/local_ai.rs) ---

type TierOverride = "auto" | "T0" | "T1" | "T2" | "T3" | "T4";

interface Tier {
  active: TierLevel;
  override: TierOverride;
}

interface BenchmarkResult {
  date: string;
  toks_per_sec: number;
  model_id: string;
}

interface ModelEntry {
  model_id: string;
  size_mb: number;
  last_used_at: string | null;
  roles: ("chat" | "summarize" | "embed" | "code")[];
}

// --- Helpers ---

function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse rounded bg-white/5 ${className}`} />;
}

function Toast({ message, onClose }: { message: string; onClose: () => void }) {
  useEffect(() => {
    const t = setTimeout(onClose, 4000);
    return () => clearTimeout(t);
  }, [onClose]);
  return (
    <div className="fixed bottom-4 right-4 z-50 rounded-lg bg-red-900/80 px-4 py-2 text-sm text-red-200 shadow-lg">
      {message}
    </div>
  );
}

function ConfirmModal({
  title,
  body,
  confirmLabel,
  onConfirm,
  onCancel,
}: {
  title: string;
  body: string;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/60">
      <div className="w-80 rounded-xl border border-white/10 bg-gray-900 p-6 shadow-2xl">
        <h3 className="mb-2 text-base font-semibold text-white">{title}</h3>
        <p className="mb-5 text-sm text-gray-400">{body}</p>
        <div className="flex justify-end gap-3">
          <button
            onClick={onCancel}
            className="rounded-lg px-4 py-1.5 text-sm text-gray-400 hover:text-white"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-sky-500"
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

// Minimal sparkline — renders tok/s values as an inline SVG bar chart.
function Sparkline({ values }: { values: number[] }) {
  if (values.length === 0) return null;
  const max = Math.max(...values, 1);
  const w = 220;
  const h = 40;
  const bw = Math.floor(w / values.length) - 2;

  return (
    <svg width={w} height={h} className="mt-1">
      {values.map((v, i) => {
        const barH = Math.max(2, Math.round((v / max) * h));
        return (
          <rect
            key={i}
            x={i * (bw + 2)}
            y={h - barH}
            width={bw}
            height={barH}
            rx={2}
            className="fill-sky-500/70"
          />
        );
      })}
    </svg>
  );
}

// --- Main component ---

export default function LocalAiSettingsPage(): React.ReactElement {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [tier, setTier] = useState<Tier>({ active: 2, override: "auto" });
  const [benchmarks, setBenchmarks] = useState<BenchmarkResult[]>([]);
  const [models, setModels] = useState<ModelEntry[]>([]);

  const [allowT4, setAllowT4] = useState(false);
  const [reBenchMonthly, setReBenchMonthly] = useState(true);

  const [benchRunning, setBenchRunning] = useState(false);
  const [importRunning, setImportRunning] = useState(false);

  // Modals
  const [confirmT4, setConfirmT4] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const [t, b, m] = await Promise.all([
        invoke<Tier>("get_tier"),
        invoke<BenchmarkResult[]>("get_benchmark_history", { limit: 12 }),
        invoke<ModelEntry[]>("list_models"),
      ]);
      setTier(t);
      setBenchmarks(b);
      setModels(m);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const handleTierOverride = useCallback(async (value: TierOverride) => {
    try {
      const override = value === "auto" ? null : (parseInt(value.slice(1)) as TierLevel);
      await invoke("set_tier_override", { tier: override });
      await load();
    } catch (e) {
      setError(String(e));
    }
  }, [load]);

  const handleAllowT4Toggle = useCallback(async (checked: boolean) => {
    if (checked) {
      setConfirmT4(true);
    } else {
      try {
        await invoke("set_allow_t4", { allow: false });
        setAllowT4(false);
      } catch (e) {
        setError(String(e));
      }
    }
  }, []);

  const confirmEnableT4 = useCallback(async () => {
    try {
      await invoke("set_allow_t4", { allow: true });
      setAllowT4(true);
    } catch (e) {
      setError(String(e));
    } finally {
      setConfirmT4(false);
    }
  }, []);

  const handleReBenchToggle = useCallback(async (checked: boolean) => {
    try {
      await invoke("set_re_bench_monthly", { enabled: checked });
      setReBenchMonthly(checked);
    } catch (e) {
      setError(String(e));
    }
  }, []);

  const runBenchmark = useCallback(async () => {
    try {
      setBenchRunning(true);
      await invoke("run_benchmark");
      await load();
    } catch (e) {
      setError(String(e));
    } finally {
      setBenchRunning(false);
    }
  }, [load]);

  const handleImportGGUF = useCallback(async () => {
    try {
      setImportRunning(true);
      const path = await invoke<string>("import_custom_gguf", { path: "" });
      if (path) await load();
    } catch (e) {
      setError(String(e));
    } finally {
      setImportRunning(false);
    }
  }, [load]);

  const handleDeleteModel = useCallback(async (modelId: string) => {
    try {
      await invoke("delete_model", { modelId });
      setModels((prev) => prev.filter((m) => m.model_id !== modelId));
    } catch (e) {
      setError(String(e));
    } finally {
      setDeleteTarget(null);
    }
  }, []);

  const handleSetChatRole = useCallback(async (modelId: string) => {
    try {
      await invoke("set_model_role", { modelId, role: "chat" });
      await load();
    } catch (e) {
      setError(String(e));
    }
  }, [load]);

  // --- Render: Loading ---
  if (loading) {
    return (
      <div className="mx-auto max-w-2xl space-y-6 p-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-20 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  const sparklValues = benchmarks.map((b) => b.toks_per_sec);
  const latestBench = benchmarks[0];

  return (
    <>
      {error && <Toast message={error} onClose={() => setError(null)} />}

      {confirmT4 && (
        <ConfirmModal
          title="Enable T4 (Heavy) models?"
          body="T4 models require 16 GB+ RAM and will fully occupy your GPU during inference. Battery drain will be significant on laptops."
          confirmLabel="Enable T4"
          onConfirm={confirmEnableT4}
          onCancel={() => setConfirmT4(false)}
        />
      )}

      {deleteTarget && (
        <ConfirmModal
          title="Delete model?"
          body={`Remove "${deleteTarget}" from disk? This cannot be undone.`}
          confirmLabel="Delete"
          onConfirm={() => handleDeleteModel(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
        />
      )}

      <div className="mx-auto max-w-2xl space-y-8 p-6">
        {/* Header */}
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-semibold text-white">Local AI</h1>
          <TierBadge tier={tier.active} isOverride={tier.override !== "auto"} />
        </div>

        {/* Tier override */}
        <section className="rounded-xl border border-white/10 bg-surface-soft p-5">
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
            Tier override
          </h2>
          <select
            value={tier.override}
            onChange={(e) => handleTierOverride(e.target.value as TierOverride)}
            className="w-full rounded-lg border border-white/10 bg-gray-900 px-3 py-2 text-sm text-white focus:border-sky-500 focus:outline-none"
          >
            <option value="auto">Auto (recommended)</option>
            <option value="T0">T0 — Nano (&lt;1 GB)</option>
            <option value="T1">T1 — Small (1-4 GB)</option>
            <option value="T2">T2 — Medium (4-8 GB)</option>
            <option value="T3">T3 — Large (8-16 GB)</option>
            <option value="T4">T4 — Heavy (16 GB+)</option>
          </select>
        </section>

        {/* Toggles */}
        <section className="rounded-xl border border-white/10 bg-surface-soft p-5 space-y-4">
          <Toggle
            label="Allow T4 (heavy models)"
            description="Requires 16 GB+ RAM. Confirmation required on first enable."
            checked={allowT4}
            onChange={handleAllowT4Toggle}
          />
          <div className="border-t border-white/5" />
          <Toggle
            label="Re-benchmark monthly"
            description="Automatically re-run the hardware benchmark every 30 days."
            checked={reBenchMonthly}
            onChange={handleReBenchToggle}
          />
        </section>

        {/* Benchmark history */}
        <section className="rounded-xl border border-white/10 bg-surface-soft p-5">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
              Benchmark history
            </h2>
            {latestBench && (
              <span className="text-xs text-gray-500">
                Last: {latestBench.toks_per_sec} tok/s · {latestBench.date}
              </span>
            )}
          </div>
          {benchmarks.length === 0 ? (
            <p className="text-sm text-gray-500">No benchmarks yet. Run one below.</p>
          ) : (
            <Sparkline values={sparklValues} />
          )}
          <button
            onClick={runBenchmark}
            disabled={benchRunning}
            className="mt-4 rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-50"
          >
            {benchRunning ? "Running..." : "Run benchmark again"}
          </button>
        </section>

        {/* Installed models */}
        <section className="rounded-xl border border-white/10 bg-surface-soft p-5">
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
            Installed models
          </h2>
          {models.length === 0 ? (
            <p className="text-sm text-gray-500">No models installed. Add a custom GGUF below.</p>
          ) : (
            <ul className="space-y-3">
              {models.map((m) => (
                <li
                  key={m.model_id}
                  className="flex items-start justify-between gap-4 rounded-lg bg-gray-900/50 px-4 py-3"
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-white">{m.model_id}</p>
                    <p className="mt-0.5 text-xs text-gray-500">
                      {(m.size_mb / 1024).toFixed(1)} GB
                      {m.last_used_at ? ` · last used ${m.last_used_at}` : ""}
                    </p>
                    <div className="mt-1.5 flex flex-wrap gap-1">
                      {m.roles.map((r) => (
                        <span
                          key={r}
                          className="rounded-full bg-sky-500/15 px-2 py-0.5 text-xs text-sky-400"
                        >
                          {r}
                        </span>
                      ))}
                    </div>
                  </div>
                  <div className="flex shrink-0 flex-col gap-1.5 pt-0.5">
                    <button
                      onClick={() => handleSetChatRole(m.model_id)}
                      className="rounded px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10"
                    >
                      Set as chat role
                    </button>
                    <button
                      onClick={() => setDeleteTarget(m.model_id)}
                      className="rounded px-2 py-1 text-xs text-red-400 hover:bg-red-500/10"
                    >
                      Delete
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        {/* Add custom GGUF */}
        <section className="rounded-xl border border-white/10 bg-surface-soft p-5">
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
            Add custom GGUF
          </h2>
          <p className="mb-3 text-sm text-gray-500">
            Import a .gguf model file from disk. It will be registered and available for role assignment.
          </p>
          <button
            onClick={handleImportGGUF}
            disabled={importRunning}
            className="rounded-lg border border-white/10 bg-gray-900 px-4 py-1.5 text-sm text-white hover:border-sky-500/50 disabled:opacity-50"
          >
            {importRunning ? "Importing..." : "Choose file..."}
          </button>
        </section>
      </div>
    </>
  );
}

// --- Toggle sub-component ---
interface ToggleProps {
  label: string;
  description: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}

function Toggle({ label, description, checked, onChange }: ToggleProps) {
  return (
    <div className="flex items-center justify-between gap-4">
      <div>
        <p className="text-sm font-medium text-white">{label}</p>
        <p className="text-xs text-gray-500">{description}</p>
      </div>
      <button
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus:outline-none ${
          checked ? "bg-sky-500" : "bg-gray-700"
        }`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${
            checked ? "translate-x-4" : "translate-x-0"
          }`}
        />
      </button>
    </div>
  );
}
