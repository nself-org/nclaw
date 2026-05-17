// ɳClaw Desktop — useStreamMetrics hook (T04)
//
// Computes TPS (tokens per second) and TTFT (time-to-first-token) from
// StreamingBuffer events at a 4Hz update rate (requestAnimationFrame throttle).

import { useCallback, useEffect, useRef, useState } from "react";
import type { StreamMetrics } from "@/types/llm";
import type { StreamingBuffer } from "@/lib/streaming-buffer";

/** Update frequency cap: 4 Hz = 250ms minimum between renders. */
const UPDATE_INTERVAL_MS = 250;

export function useStreamMetrics(buffer: StreamingBuffer): StreamMetrics {
  const [metrics, setMetrics] = useState<StreamMetrics>({
    tps: null,
    ttft_ms: null,
  });

  // Timing state — stored in refs to avoid stale closures.
  const startRef = useRef<number | null>(null);
  const firstTokenRef = useRef<number | null>(null);
  const tokenCountRef = useRef(0);
  const lastUpdateRef = useRef(0);
  const rafRef = useRef<number | null>(null);

  const computeMetrics = useCallback(() => {
    const now = performance.now();
    if (now - lastUpdateRef.current < UPDATE_INTERVAL_MS) {
      return;
    }
    lastUpdateRef.current = now;

    const ttft_ms =
      startRef.current !== null && firstTokenRef.current !== null
        ? Math.round(firstTokenRef.current - startRef.current)
        : null;

    const elapsed =
      firstTokenRef.current !== null
        ? (now - firstTokenRef.current) / 1000
        : null;

    const tps =
      elapsed !== null && elapsed > 0 && tokenCountRef.current > 0
        ? Math.round(tokenCountRef.current / elapsed)
        : null;

    setMetrics({ tps, ttft_ms });
  }, []);

  useEffect(() => {
    // Reset on new buffer.
    startRef.current = performance.now();
    firstTokenRef.current = null;
    tokenCountRef.current = 0;
    lastUpdateRef.current = 0;
    setMetrics({ tps: null, ttft_ms: null });

    const unsubscribe = buffer.subscribe((_text) => {
      tokenCountRef.current += 1;

      // Record time of first token.
      if (firstTokenRef.current === null) {
        firstTokenRef.current = performance.now();
      }

      // Throttle via rAF.
      if (rafRef.current !== null) return;
      rafRef.current = requestAnimationFrame(() => {
        rafRef.current = null;
        computeMetrics();
      });
    });

    return () => {
      unsubscribe();
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
    };
  }, [buffer, computeMetrics]);

  return metrics;
}
