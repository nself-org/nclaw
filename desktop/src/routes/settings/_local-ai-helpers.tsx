/**
 * Local AI settings — shared types and UI micro-components.
 *
 * Extracted from local-ai.tsx to keep the main page under 300 lines.
 * Import via `import { ..., Toggle, Sparkline, ... } from "./_local-ai-helpers"`.
 */

import { useEffect } from "react";
import { TierLevel } from "../../components/tier-badge";

// ---------------------------------------------------------------------------
// Types (mirror commands/local_ai.rs)
// ---------------------------------------------------------------------------

export type TierOverride = "auto" | "T0" | "T1" | "T2" | "T3" | "T4";

/** Active tier + user override selection for the Local AI settings page. */
export interface Tier {
  active: TierLevel;
  override: TierOverride;
}

/** A single benchmark history entry returned by the `get_benchmark_history` Tauri command. */
export interface BenchmarkResult {
  date: string;
  toks_per_sec: number;
  model_id: string;
}

/** A cached model entry returned by the `list_models` Tauri command. */
export interface ModelEntry {
  model_id: string;
  size_mb: number;
  last_used_at: string | null;
  roles: ("chat" | "summarize" | "embed" | "code")[];
}

// ---------------------------------------------------------------------------
// Micro-components
// ---------------------------------------------------------------------------

/** Animated shimmer placeholder used during initial data load. */
export function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse rounded bg-white/5 ${className}`} />;
}

/** Transient error toast that auto-dismisses after 4 seconds. */
export function Toast({ message, onClose }: { message: string; onClose: () => void }) {
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

/** Confirmation modal with cancel and confirm actions. */
export function ConfirmModal({
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

/** Inline SVG bar chart showing tok/s values over time. */
export function Sparkline({ values }: { values: number[] }) {
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

/** Installed models list with per-model role and delete actions. */
export function ModelsList({
  models,
  onSetChatRole,
  onDeleteRequest,
}: {
  models: ModelEntry[];
  onSetChatRole: (modelId: string) => void;
  onDeleteRequest: (modelId: string) => void;
}) {
  return (
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
                  onClick={() => onSetChatRole(m.model_id)}
                  className="rounded px-2 py-1 text-xs text-sky-400 hover:bg-sky-500/10"
                >
                  Set as chat role
                </button>
                <button
                  onClick={() => onDeleteRequest(m.model_id)}
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
  );
}

/** Labelled toggle switch with a description line. */
export interface ToggleProps {
  label: string;
  description: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}

export function Toggle({ label, description, checked, onChange }: ToggleProps) {
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
