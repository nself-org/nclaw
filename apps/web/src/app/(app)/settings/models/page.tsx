'use client';

import React, { useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ModelPicker } from '@/components/models/ModelPicker';
import { useAppStore } from '@/store/app-store';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import api from '@/lib/api';
import type { ModelSelection } from '@/types';

export default function ModelSettingsPage(): React.ReactElement {
  const { isOnline } = useNetworkStatus();
  const storeSelection = useAppStore((s) => s.settings?.modelSelection);
  const updateModelSelection = useAppStore((s) => s.updateModelSelection);
  const setSettings = useAppStore((s) => s.setSettings);
  const settings = useAppStore((s) => s.settings);

  const [saved, setSaved] = React.useState(false);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Hydrate model selection from server on mount
  const { data: serverSelection } = useQuery<ModelSelection, Error>({
    queryKey: ['model-selection'],
    queryFn: async () => {
      const r = await api.getModelSelection();
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
    staleTime: 30_000,
  });

  const hydrated = useRef(false);
  useEffect(() => {
    if (serverSelection && !hydrated.current) {
      hydrated.current = true;
      if (settings) {
        setSettings({ ...settings, modelSelection: serverSelection });
      } else {
        updateModelSelection(serverSelection);
      }
    }
  }, [serverSelection, settings, setSettings, updateModelSelection]);

  // Listen for store changes to show save confirmation
  const prevSelectionRef = useRef(storeSelection);
  useEffect(() => {
    const prev = prevSelectionRef.current;
    const curr = storeSelection;
    if (
      prev !== undefined &&
      curr !== undefined &&
      JSON.stringify(prev) !== JSON.stringify(curr)
    ) {
      setSaved(true);
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(() => setSaved(false), 2500);
    }
    prevSelectionRef.current = curr;
  }, [storeSelection]);

  useEffect(() => {
    return () => {
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    };
  }, []);

  return (
    <main className="mx-auto max-w-xl w-full px-4 py-10 flex flex-col gap-8">
      <OfflineBanner isOnline={isOnline} />
      <header style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '12px' }}>
        <div>
          <h1
            className="text-2xl font-semibold"
            style={{ color: 'var(--color-text)', margin: 0 }}
          >
            AI Model
          </h1>
          <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)', margin: '4px 0 0' }}>
            Choose how ɳClaw selects the AI model for your conversations.
          </p>
        </div>

        {saved && (
          <span
            role="status"
            aria-live="polite"
            style={{
              fontSize: '13px',
              color: 'var(--color-success)',
              fontWeight: 500,
              whiteSpace: 'nowrap',
              paddingTop: '6px',
              flexShrink: 0,
            }}
          >
            Saved
          </span>
        )}
      </header>

      <ModelPicker />
    </main>
  );
}
