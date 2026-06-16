/**
 * Purpose: Client-side wrapper that mounts the @nself/claw-web ClawWebRoot context
 *          around the nclaw/apps/web Next.js application.
 * Inputs:  children — the Next.js page subtree
 * Outputs: ClawWebRoot wrapping children with PWA support (service worker, offline banner,
 *          PWA install prompt)
 * Constraints: Must be 'use client' — ClawWebRoot uses browser APIs (serviceWorker, online
 *              status). Do not import in server components. PWA is enabled by default.
 * SPORT: T-P3-E4-W3-S8-T05 — claw-web consumer wire
 */
'use client';

import { ClawWebRoot } from '@nself/claw-web';
import type { ReactNode } from 'react';

interface ClawWebProviderProps {
  children: ReactNode;
}

/**
 * ClawWebProvider — mounts @nself/claw-web context in the Next.js app shell.
 * Registered in src/app/layout.tsx as a client boundary wrapping page content.
 */
export function ClawWebProvider({ children }: ClawWebProviderProps) {
  return <ClawWebRoot>{children}</ClawWebRoot>;
}
