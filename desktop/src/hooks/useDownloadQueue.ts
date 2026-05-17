// ɳClaw Desktop — useDownloadQueue hook (T02)
//
// Manages the model download queue. Bridges Tauri commands and the
// `llm://download-progress` event into a reactive Zustand-like state.

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { useCallback, useEffect, useRef, useState } from "react";
import type { DownloadEntry, DownloadProgress } from "@/types/llm";

export interface UseDownloadQueueReturn {
  /** Current download queue. */
  queue: DownloadEntry[];
  /** True while the initial queue list is loading. */
  loading: boolean;
  /** Enqueue and start a new download. Returns the download ID. */
  startDownload: (
    url: string,
    filename: string,
    expectedSha256?: string
  ) => Promise<string>;
  /** Cancel a queued or in-progress download. */
  cancelDownload: (id: string) => Promise<void>;
  /** Reload the queue from the backend. */
  refresh: () => Promise<void>;
}

export function useDownloadQueue(): UseDownloadQueueReturn {
  const [queue, setQueue] = useState<DownloadEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const unlistenRef = useRef<UnlistenFn | null>(null);

  const refresh = useCallback(async () => {
    try {
      const list = await invoke<DownloadEntry[]>("llm_download_list");
      setQueue(list);
    } catch (err) {
      console.error("[useDownloadQueue] list error:", err);
    }
  }, []);

  useEffect(() => {
    // Initial load.
    refresh().finally(() => setLoading(false));

    // Subscribe to progress events from the backend.
    let mounted = true;
    listen<DownloadProgress>("llm://download-progress", (event) => {
      if (!mounted) return;
      const progress = event.payload;
      setQueue((prev) =>
        prev.map((entry) =>
          entry.id === progress.id
            ? {
                ...entry,
                status: progress.status,
                bytes_received: progress.bytes_received,
                total_bytes: progress.total_bytes ?? entry.total_bytes,
              }
            : entry
        )
      );
    }).then((unlisten) => {
      if (mounted) {
        unlistenRef.current = unlisten;
      } else {
        unlisten();
      }
    });

    return () => {
      mounted = false;
      unlistenRef.current?.();
    };
  }, [refresh]);

  const startDownload = useCallback(
    async (url: string, filename: string, expectedSha256?: string) => {
      const id = await invoke<string>("llm_download_start", {
        url,
        filename,
        expectedSha256: expectedSha256 ?? null,
      });
      // Optimistically add to queue.
      setQueue((prev) => [
        ...prev,
        {
          id,
          url,
          filename,
          expected_sha256: expectedSha256 ?? null,
          status: "queued" as const,
          bytes_received: 0,
          total_bytes: null,
        },
      ]);
      return id;
    },
    []
  );

  const cancelDownload = useCallback(async (id: string) => {
    await invoke("llm_download_cancel", { id });
    setQueue((prev) =>
      prev.map((entry) =>
        entry.id === id ? { ...entry, status: "cancelled" as const } : entry
      )
    );
  }, []);

  return { queue, loading, startDownload, cancelDownload, refresh };
}
