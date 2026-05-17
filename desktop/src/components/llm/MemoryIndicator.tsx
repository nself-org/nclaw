// ɳClaw Desktop — MemoryIndicator component (T05)
//
// Compact status bar pill showing GPU VRAM + system RAM usage.
// Subscribes to llm://memory-snapshot events via useMemoryMonitor.

import { useMemoryMonitor } from "@/hooks/useMemoryMonitor";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatMb(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
  return `${Math.round(mb)} MB`;
}

function usagePercent(used: number, total: number): number {
  if (total === 0) return 0;
  return Math.min(100, Math.round((used / total) * 100));
}

function barColor(pct: number): string {
  if (pct >= 90) return "bg-red-500";
  if (pct >= 70) return "bg-amber-400";
  return "bg-sky-500";
}

// ---------------------------------------------------------------------------
// Sub-component — a single labeled progress bar
// ---------------------------------------------------------------------------

function MemBar({
  label,
  used,
  total,
}: {
  label: string;
  used: number;
  total: number;
}) {
  const pct = usagePercent(used, total);
  const color = barColor(pct);

  return (
    <div className="flex items-center gap-2 min-w-0">
      <span className="text-xs text-slate-400 shrink-0 w-10">{label}</span>
      <div
        role="meter"
        aria-label={`${label} usage`}
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
        className="flex-1 h-1.5 rounded-full bg-slate-700 overflow-hidden"
      >
        <div
          className={`h-full rounded-full transition-all ${color}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="text-xs text-slate-300 shrink-0 tabular-nums">
        {total > 0
          ? `${formatMb(used)} / ${formatMb(total)}`
          : "unavailable"}
      </span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

interface MemoryIndicatorProps {
  /** Render as an inline row instead of a stacked column (default stacked). */
  inline?: boolean;
}

export function MemoryIndicator({ inline = false }: MemoryIndicatorProps) {
  const { snapshot, loading } = useMemoryMonitor();

  if (loading) {
    return (
      <span className="text-xs text-slate-500 animate-pulse" aria-live="polite">
        Measuring memory…
      </span>
    );
  }

  const hasGpu = snapshot.gpu_total_mb > 0;

  return (
    <div
      className={`${inline ? "flex gap-4" : "flex flex-col gap-1.5"} min-w-0`}
      aria-label="Memory usage"
    >
      {hasGpu && (
        <MemBar
          label="VRAM"
          used={snapshot.gpu_used_mb}
          total={snapshot.gpu_total_mb}
        />
      )}
      <MemBar
        label="RAM"
        used={snapshot.ram_used_mb}
        total={snapshot.ram_total_mb}
      />
      {snapshot.source && (
        <span className="text-xs text-slate-600" aria-hidden="true">
          {snapshot.source}
        </span>
      )}
    </div>
  );
}
