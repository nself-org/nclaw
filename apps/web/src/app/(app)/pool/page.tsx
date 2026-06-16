'use client';

import React from 'react';
import { PoolManager } from '@/components/pool/PoolManager';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';

export default function PoolPage(): React.ReactElement {
  const { isOnline } = useNetworkStatus();

  return (
    <main className="mx-auto max-w-2xl w-full px-4 py-10 flex flex-col gap-8">
      <OfflineBanner isOnline={isOnline} />

      <header>
        <h1
          className="text-2xl font-semibold"
          style={{ color: 'var(--color-text)', margin: 0 }}
        >
          Account Pool
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)', margin: '4px 0 0' }}>
          Connected accounts let ɳClaw access your email, calendar, and other services.
        </p>
      </header>

      <PoolManager />
    </main>
  );
}
