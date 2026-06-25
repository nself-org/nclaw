/**
 * Local AI Settings page — tier override, benchmark history, installed models, custom GGUF import.
 *
 * Tauri commands are defined in src-tauri/src/commands/local_ai.rs (stubs; wired in S15.T17).
 * Types and UI micro-components are in `./_local-ai-helpers.tsx`.
 */
import React, { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { TierBadge } from "../../components/tier-badge";
import {
  BenchmarkResult,
  ConfirmModal,
  ModelEntry,
  ModelsList,
  Skeleton,
  Sparkline,
  Tier,
  TierOverride,
  Toast,
  Toggle,
} from "./_local-ai-helpers";

/** Local AI settings page: tier override select, benchmark sparkline, installed model list, and GGUF import. */
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

  const handleTierOverride = useCallback(
    async (value: TierOverride) => {
      try {
        const override = value === "auto" ? null : (parseInt(value.slice(1)) as Tier["active"]);
        await invoke("set_tier_override", { tier: override });
        await load();
      } catch (e) {
        setError(String(e));
      }
    },
    [load],
  );

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

  const handleSetChatRole = useCallback(
    async (modelId: string) => {
      try {
        await invoke("set_model_role", { modelId, role: "chat" });
        await load();
      } catch (e) {
        setError(String(e));
      }
    },
    [load],
  );

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
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-semibold text-white">Local AI</h1>
          <TierBadge tier={tier.active} isOverride={tier.override !== "auto"} />
        </div>

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

        <ModelsList
          models={models}
          onSetChatRole={handleSetChatRole}
          onDeleteRequest={setDeleteTarget}
        />

        <section className="rounded-xl border border-white/10 bg-surface-soft p-5">
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
            Add custom GGUF
          </h2>
          <p className="mb-3 text-sm text-gray-500">
            Import a .gguf model file from disk. It will be registered and available for role
            assignment.
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
