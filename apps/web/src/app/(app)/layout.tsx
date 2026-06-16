'use client';

import { useEffect, useRef } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useAppStore } from '@/store/app-store';
import { Sidebar } from '@/components/layout/Sidebar';
import { TopBar } from '@/components/layout/TopBar';
import { ErrorBoundary } from '@/components/ErrorBoundary';

const W_SIDEBAR_SLIDE = 280;

export default function AppShellLayout({ children }: { children: React.ReactNode }) {
  const { sidebarOpen, setSidebarOpen } = useAppStore();
  const overlayRef = useRef<HTMLDivElement>(null);

  // Close mobile drawer on Escape
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape' && sidebarOpen) setSidebarOpen(false);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [sidebarOpen, setSidebarOpen]);

  // Move focus into the drawer when it opens on mobile
  useEffect(() => {
    if (!sidebarOpen) return;
    const firstFocusable = overlayRef.current?.querySelector<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );
    firstFocusable?.focus();
  }, [sidebarOpen]);

  return (
    <div
      className="flex h-screen overflow-hidden"
      style={{ background: 'var(--color-bg)' }}
    >
      {/* Desktop sidebar — always in flow, width is animated inside Sidebar itself */}
      <div className="hidden md:flex flex-shrink-0" style={{ position: 'relative', zIndex: 20 }}>
        <Sidebar />
      </div>

      {/* Mobile drawer overlay */}
      <AnimatePresence>
        {sidebarOpen && (
          <>
            {/* Backdrop */}
            <motion.div
              key="backdrop"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="md:hidden fixed inset-0 z-30"
              style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(2px)' }}
              onClick={() => setSidebarOpen(false)}
              aria-hidden="true"
            />

            {/* Drawer */}
            <motion.div
              key="drawer"
              ref={overlayRef}
              initial={{ x: -W_SIDEBAR_SLIDE }}
              animate={{ x: 0 }}
              exit={{ x: -W_SIDEBAR_SLIDE }}
              transition={{ duration: 0.25, ease: 'easeOut' }}
              className="md:hidden fixed inset-y-0 left-0 z-40 flex"
              role="dialog"
              aria-modal="true"
              aria-label="Navigation sidebar"
            >
              <Sidebar />
            </motion.div>
          </>
        )}
      </AnimatePresence>

      {/* Main content — flex-1 fills space left by the in-flow desktop sidebar */}
      <main
        className="flex flex-col flex-1 min-w-0 h-screen overflow-hidden"
        aria-label="Main content"
      >
        <TopBar />
        <div className="flex-1 overflow-y-auto">
          <ErrorBoundary>{children}</ErrorBoundary>
        </div>
      </main>
    </div>
  );
}
