/**
 * Auth-route error boundary — Next.js App Router native error page.
 *
 * Purpose: Catch errors in login / onboarding routes so they show a
 *          recovery UI instead of a blank screen.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */

'use client';

import { ErrorCard } from '@/components/ErrorBoundary';

interface ErrorPageProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function AuthRouteError({
  error,
  reset: _reset,
}: ErrorPageProps) {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <ErrorCard message={error.message} />
    </div>
  );
}
