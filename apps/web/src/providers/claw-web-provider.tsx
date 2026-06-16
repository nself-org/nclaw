/**
 * Purpose: Client-side wrapper that mounts the @nself/claw-web ClawWebRoot context
 *          around the nclaw/apps/web Next.js application, and initializes Sentry.
 * Inputs:  children — the Next.js page subtree
 * Outputs: ClawWebRoot wrapping children with PWA support (service worker, offline banner,
 *          PWA install prompt) and Sentry error boundary
 * Constraints: Must be 'use client' — ClawWebRoot uses browser APIs (serviceWorker, online
 *              status). Do not import in server components. PWA is enabled by default.
 * SPORT: T-P3-E4-W3-S8-T05 — claw-web consumer wire; T-P3-E5-W1-S1-T05 — Sentry init
 */
'use client';

import { ClawWebRoot } from '@nself/claw-web';
import type { ReactNode } from 'react';
import { useEffect } from 'react';
import { ErrorBoundaryWrapper } from '@/components/error-boundary';
import { initializeSentry } from '@/lib/sentry';

interface ClawWebProviderProps {
  children: ReactNode;
}

/**
 * ClawWebProvider — mounts @nself/claw-web context in the Next.js app shell.
 * Also initializes Sentry for error tracking and performance monitoring.
 * Registered in src/app/layout.tsx as a client boundary wrapping page content.
 */
export function ClawWebProvider({ children }: ClawWebProviderProps) {
  useEffect(() => {
    // Initialize Sentry on client mount
    initializeSentry();
  }, []);

  return (
    <ErrorBoundaryWrapper>
      <ClawWebRoot>{children}</ClawWebRoot>
    </ErrorBoundaryWrapper>
  );
}
