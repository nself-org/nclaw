// ɳClaw Desktop — DownloadQueue component (T02)
//
// Displays active and recent model downloads. Allows cancellation of
// in-progress downloads. Driven entirely by the useDownloadQueue hook.

import { useDownloadQueue } from "@/hooks/useDownloadQueue";
import { Button } from "@/components/ui/button";
import type { DownloadEntry } from "@/types/llm";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const gb = bytes / 1024 ** 3;
  if (gb >= 1) return `${gb.toFixed(2)} GB`;
  const mb = bytes / 1024 ** 2;
  if (mb >= 1) return `${mb.toFixed(1)} MB`;
  const kb = bytes / 1024;
  return `${Math.round(kb)} KB`;
}

function progressPercent(entry: DownloadEntry): number | null {
  if (!entry.total_bytes || entry.total_bytes === 0) return null;
  return Math.min(100, Math.round((entry.bytes_received / entry.total_bytes) * 100));
}

function statusLabel(entry: DownloadEntry): string {
  if (entry.status === "queued") return "Queued";
  if (entry.status === "downloading") {
    const pct = progressPercent(entry);
    const received = formatBytes(entry.bytes_received);
    const total = entry.total_bytes ? ` / ${formatBytes(entry.total_bytes)}` : "";
    return pct !== null
      ? `${pct}% — ${received}${total}`
      : `Downloading ${received}${total}`;
  }
  if (entry.status === "verifying") return "Verifying…";
  if (entry.status === "done") return "Done";
  if (entry.status === "cancelled") return "Cancelled";
  if (typeof entry.status === "object" && "failed" in entry.status)
    return `Failed: ${entry.status.failed}`;
  return String(entry.status);
}

function isActive(entry: DownloadEntry): boolean {
  return (
    entry.status === "queued" ||
    entry.status === "downloading" ||
    entry.status === "verifying"
  );
}

function statusColor(entry: DownloadEntry): string {
  if (entry.status === "done") return "text-green-400";
  if (entry.status === "cancelled") return "text-slate-400";
  if (typeof entry.status === "object" && "failed" in entry.status)
    return "text-red-400";
  return "text-slate-300";
}

// ---------------------------------------------------------------------------
// Sub-component — single download row
// ---------------------------------------------------------------------------

function DownloadRow({
  entry,
  onCancel,
}: {
  entry: DownloadEntry;
  onCancel: (id: string) => void;
}) {
  const pct = progressPercent(entry);
  const active = isActive(entry);

  return (
    <li className="px-3 py-2 space-y-1">
      <div className="flex items-center justify-between gap-2">
        <span
          className="text-sm font-medium text-slate-100 truncate min-w-0"
          title={entry.filename}
        >
          {entry.filename}
        </span>
        {active && (
          <Button
            size="sm"
            variant="ghost"
            className="shrink-0 h-6 px-2 text-xs text-slate-400 hover:text-red-400"
            onClick={() => onCancel(entry.id)}
            aria-label={`Cancel download of ${entry.filename}`}
          >
            Cancel
          </Button>
        )}
      </div>

      {/* Progress bar — only shown while downloading */}
      {entry.status === "downloading" && pct !== null && (
        <div
          role="progressbar"
          aria-valuenow={pct}
          aria-valuemin={0}
          aria-valuemax={100}
          className="h-1 rounded-full bg-slate-700 overflow-hidden"
        >
          <div
            className="h-full bg-sky-500 transition-all"
            style={{ width: `${pct}%` }}
          />
        </div>
      )}

      <p className={`text-xs ${statusColor(entry)}`}>{statusLabel(entry)}</p>
    </li>
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function DownloadQueue() {
  const { queue, loading, cancelDownload } = useDownloadQueue();

  if (loading) {
    return (
      <p className="text-xs text-slate-400 px-3 py-2" aria-live="polite">
        Loading downloads…
      </p>
    );
  }

  if (queue.length === 0) {
    return null;
  }

  return (
    <section aria-label="Model download queue">
      <h3 className="px-3 pt-3 pb-1 text-xs font-semibold uppercase tracking-wider text-slate-500">
        Downloads
      </h3>
      <ul
        className="divide-y divide-slate-700 rounded border border-slate-700"
        aria-label="Download list"
      >
        {queue.map((entry) => (
          <DownloadRow key={entry.id} entry={entry} onCancel={cancelDownload} />
        ))}
      </ul>
    </section>
  );
}
