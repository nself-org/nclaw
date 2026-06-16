/**
 * App-shell route error boundary — Next.js App Router native error page.
 *
 * Purpose: Catch server-side + async errors that escape React render and
 *          display a recovery UI instead of a blank screen. Complements
 *          the client-side ErrorBoundary component in layout.tsx.
 *
 * Inputs:  error — the thrown Error, reset — function to retry the segment.
 * Outputs: ErrorCard with Reload CTA wired to the Next.js reset function.
 *
 * Constraints:
 *   - Must be 'use client' (Next.js requirement for error.tsx files).
 *   - reset() re-renders the route segment; use for transient failures.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */

'use client';

import { ErrorCard } from '@/components/ErrorBoundary';

interface ErrorPageProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function AppRouteError({
  error,
  reset: _reset,
}: ErrorPageProps) {
  return (
    <div className="flex-1 flex items-center justify-center h-full">
      <ErrorCard message={error.message} />
    </div>
  );
}
