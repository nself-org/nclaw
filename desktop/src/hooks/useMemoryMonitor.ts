// ɳClaw Desktop — useMemoryMonitor hook (T05)
//
// Subscribes to `llm://memory-snapshot` events from the Rust telemetry task.
// Starts polling on mount, stops on unmount.

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { useEffect, useRef, useState } from "react";
import type { MemorySnapshot } from "@/types/llm";

const EMPTY_SNAPSHOT: MemorySnapshot = {
  gpu_used_mb: 0,
  gpu_total_mb: 0,
  ram_used_mb: 0,
  ram_total_mb: 0,
  source: "",
};

export interface UseMemoryMonitorReturn {
  snapshot: MemorySnapshot;
  /** True while the first snapshot has not yet arrived. */
  loading: boolean;
}

export function useMemoryMonitor(): UseMemoryMonitorReturn {
  const [snapshot, setSnapshot] = useState<MemorySnapshot>(EMPTY_SNAPSHOT);
  const [loading, setLoading] = useState(true);
  const unlistenRef = useRef<UnlistenFn | null>(null);

  useEffect(() => {
    let mounted = true;

    // Start the Rust telemetry task (idempotent on the Rust side).
    invoke("llm_telemetry_start").catch((e) =>
      console.error("[useMemoryMonitor] start error:", e)
    );

    listen<MemorySnapshot>("llm://memory-snapshot", (event) => {
      if (!mounted) return;
      setSnapshot(event.payload);
      setLoading(false);
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
      // Stop telemetry polling when the component unmounts.
      invoke("llm_telemetry_stop").catch(() => {});
    };
  }, []);

  return { snapshot, loading };
}
