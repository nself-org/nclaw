'use client';

import { useCallback, useRef } from 'react';

/**
 * useAbortableRequest
 *
 * Purpose: Returns a stable `invoke` function that automatically cancels the previous
 *          in-flight request before dispatching a new one. Prevents race conditions
 *          when a component fires rapid back-to-back async calls (e.g. keystroke-driven
 *          classify, memory search, knowledge search).
 *
 * Inputs:
 *   fn — async (signal: AbortSignal, ...args: A) => Promise<R>
 *        Caller must forward the signal to fetch() or any inner async call.
 *
 * Outputs:
 *   invoke(...args) — aborts previous call, creates new AbortController, calls fn.
 *   abort()        — explicitly cancel any in-flight call (e.g. on component unmount).
 *
 * Constraints:
 *   - Only one request is in-flight at a time; earlier ones are aborted, not queued.
 *   - AbortError is re-thrown; callers should catch and ignore 'AbortError' name.
 *   - No React state — purely a ref-based guard to avoid stale renders.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: edge-case resilience
 */

export function useAbortableRequest<A extends unknown[], R>(
  fn: (signal: AbortSignal, ...args: A) => Promise<R>,
): {
  invoke: (...args: A) => Promise<R>;
  abort: () => void;
} {
  const controllerRef = useRef<AbortController | null>(null);

  const abort = useCallback(() => {
    controllerRef.current?.abort();
    controllerRef.current = null;
  }, []);

  const invoke = useCallback(
    (...args: A): Promise<R> => {
      // Cancel previous in-flight request.
      controllerRef.current?.abort();

      const controller = new AbortController();
      controllerRef.current = controller;

      return fn(controller.signal, ...args).finally(() => {
        // Clean up ref only if this specific controller is still current.
        if (controllerRef.current === controller) {
          controllerRef.current = null;
        }
      });
    },
    [fn],
  );

  return { invoke, abort };
}

export default useAbortableRequest;
