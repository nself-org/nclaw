'use client';

import React, { useCallback, useId } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { motion, AnimatePresence } from 'framer-motion';
import { Download, CheckCircle2, Zap, Scale, Star } from 'lucide-react';
import { GlassCard } from '@/components/ui/GlassCard';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Skeleton } from '@/components/ui/Skeleton';
import { Spinner } from '@/components/ui/Spinner';
import { EmptyState } from '@/components/ui/EmptyState';
import { useAppStore } from '@/store/app-store';
import api from '@/lib/api';
import type { ModelSelection, OllamaModel, SystemInfo } from '@/types';

// ─── helpers ────────────────────────────────────────────────────────────────

function ramBarColor(
  ramRequiredGb: number,
  availableRamGb: number,
): 'success' | 'warning' | 'error' {
  if (ramRequiredGb <= availableRamGb * 0.8) return 'success';
  if (ramRequiredGb <= availableRamGb) return 'warning';
  return 'error';
}

const colorMap: Record<'success' | 'warning' | 'error', string> = {
  success: 'var(--color-success)',
  warning: 'var(--color-warning)',
  error: 'var(--color-error)',
};

// ─── sub-components ──────────────────────────────────────────────────────────

interface RamBarProps {
  model: OllamaModel;
  systemInfo: SystemInfo;
}

function RamBar({ model, systemInfo }: RamBarProps): React.ReactElement {
  const { ramRequiredGb } = model;
  const { totalRamGb, availableRamGb } = systemInfo;
  const color = ramBarColor(ramRequiredGb, availableRamGb);
  const pct = Math.min(ramRequiredGb / totalRamGb, 1) * 100;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
      <div
        style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
      >
        <span style={{ fontSize: '11px', color: 'var(--color-text-muted)' }}>
          RAM required
        </span>
        <span
          style={{ fontSize: '11px', fontWeight: 500, color: colorMap[color] }}
          aria-label={`${ramRequiredGb} GB RAM required`}
        >
          {ramRequiredGb} GB
        </span>
      </div>
      <div
        role="progressbar"
        aria-valuenow={Math.round(pct)}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`RAM usage: ${ramRequiredGb} of ${totalRamGb} GB`}
        style={{
          height: '4px',
          borderRadius: '9999px',
          background: 'rgba(255,255,255,0.08)',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            height: '100%',
            width: `${pct}%`,
            borderRadius: '9999px',
            background: colorMap[color],
            transition: 'width 400ms ease',
          }}
        />
      </div>
    </div>
  );
}

interface ModelCardProps {
  model: OllamaModel;
  isSelected: boolean;
  systemInfo: SystemInfo;
  onSelect: (id: string) => void;
  onPull: (id: string) => void;
  isPulling: boolean;
}

function ModelCard({
  model,
  isSelected,
  systemInfo,
  onSelect,
  onPull,
  isPulling,
}: ModelCardProps): React.ReactElement {
  const [hovered, setHovered] = React.useState(false);

  const borderColor = isSelected
    ? 'var(--color-primary)'
    : hovered
    ? 'rgba(255,255,255,0.18)'
    : 'var(--color-border)';

  const bg = isSelected
    ? 'rgba(99,102,241,0.08)'
    : 'var(--color-bg-card)';

  function statusBadge(): React.ReactElement {
    if (model.isRunning) return <Badge variant="success">Running</Badge>;
    if (model.isInstalled) return <Badge variant="primary">Installed</Badge>;
    return <Badge variant="default">Not installed</Badge>;
  }

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        if (model.isInstalled) onSelect(model.id);
      }
    },
    [model.id, model.isInstalled, onSelect],
  );

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2, ease: 'easeOut' }}
    >
      <div
        role="radio"
        aria-checked={isSelected}
        aria-label={`Select model ${model.displayName}`}
        tabIndex={model.isInstalled ? 0 : -1}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        onKeyDown={handleKeyDown}
        onClick={() => {
          if (model.isInstalled) onSelect(model.id);
        }}
        style={{
          padding: '14px 16px',
          borderRadius: '10px',
          border: `1px solid ${borderColor}`,
          background: bg,
          cursor: model.isInstalled ? 'pointer' : 'default',
          transition: 'border-color 150ms ease, background 150ms ease',
          display: 'flex',
          flexDirection: 'column',
          gap: '10px',
          position: 'relative',
          outline: 'none',
        }}
      >
        {/* Header row */}
        <div
          style={{
            display: 'flex',
            alignItems: 'flex-start',
            justifyContent: 'space-between',
            gap: '12px',
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
              <span
                style={{
                  fontWeight: 600,
                  fontSize: '14px',
                  color: 'var(--color-text)',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {model.displayName}
              </span>
              <Badge variant="default">{model.family}</Badge>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
              <span style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>
                {model.parameterCount}
              </span>
              <span
                style={{
                  fontSize: '11px',
                  color: 'var(--color-text-muted)',
                  opacity: 0.6,
                }}
              >
                ·
              </span>
              <span style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>
                {model.quantization}
              </span>
            </div>
          </div>

          <div
            style={{ display: 'flex', alignItems: 'center', gap: '8px', flexShrink: 0 }}
          >
            {statusBadge()}
            {isSelected && (
              <CheckCircle2
                size={16}
                aria-hidden="true"
                style={{ color: 'var(--color-primary)', flexShrink: 0 }}
              />
            )}
          </div>
        </div>

        {/* RAM bar */}
        <RamBar model={model} systemInfo={systemInfo} />

        {/* Download row */}
        {!model.isInstalled && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            {model.sizeOnDiskGb !== null && (
              <span style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>
                ~{model.sizeOnDiskGb} GB download
              </span>
            )}
            <Button
              variant="outline"
              size="sm"
              loading={isPulling}
              onClick={(e) => {
                e.stopPropagation();
                onPull(model.id);
              }}
              aria-label={`Download ${model.displayName}`}
              style={{ marginLeft: 'auto' }}
            >
              {!isPulling && <Download size={13} aria-hidden="true" />}
              {isPulling ? 'Downloading…' : 'Download'}
            </Button>
          </div>
        )}
      </div>
    </motion.div>
  );
}

// ─── skeleton list ────────────────────────────────────────────────────────────

function ModelListSkeleton(): React.ReactElement {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          style={{
            padding: '14px 16px',
            borderRadius: '10px',
            border: '1px solid var(--color-border)',
            background: 'var(--color-bg-card)',
            display: 'flex',
            flexDirection: 'column',
            gap: '12px',
          }}
          aria-hidden="true"
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', flex: 1, marginRight: '12px' }}>
              <Skeleton variant="text" width="60%" height="14px" />
              <Skeleton variant="text" width="40%" height="12px" />
            </div>
            <Skeleton variant="rect" width="64px" height="22px" style={{ borderRadius: '9999px' }} />
          </div>
          <Skeleton variant="rect" width="100%" height="4px" style={{ borderRadius: '9999px' }} />
        </div>
      ))}
    </div>
  );
}

// ─── auto strategy selector ───────────────────────────────────────────────────

type AutoStrategy = ModelSelection['autoStrategy'];

interface StrategyOption {
  value: AutoStrategy;
  label: string;
  icon: React.ReactNode;
  description: string;
}

const STRATEGY_OPTIONS: StrategyOption[] = [
  {
    value: 'fastest',
    label: 'Fastest',
    icon: <Zap size={14} aria-hidden="true" />,
    description: 'Prioritises response speed',
  },
  {
    value: 'balanced',
    label: 'Balanced',
    icon: <Scale size={14} aria-hidden="true" />,
    description: 'Speed vs quality trade-off',
  },
  {
    value: 'best',
    label: 'Best Quality',
    icon: <Star size={14} aria-hidden="true" />,
    description: 'Maximum reasoning capability',
  },
];

interface StrategyPickerProps {
  value: AutoStrategy;
  onChange: (v: AutoStrategy) => void;
  groupId: string;
}

function StrategyPicker({ value, onChange, groupId }: StrategyPickerProps): React.ReactElement {
  return (
    <div
      role="radiogroup"
      aria-label="Auto model strategy"
      style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}
    >
      {STRATEGY_OPTIONS.map((opt) => {
        const checked = value === opt.value;
        const radioId = `${groupId}-strategy-${opt.value}`;
        return (
          <label
            key={opt.value}
            htmlFor={radioId}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '8px 14px',
              borderRadius: '8px',
              border: `1px solid ${checked ? 'var(--color-primary)' : 'var(--color-border)'}`,
              background: checked ? 'rgba(99,102,241,0.1)' : 'transparent',
              color: checked ? 'var(--color-primary-text)' : 'var(--color-text-muted)',
              fontSize: '13px',
              fontWeight: checked ? 500 : 400,
              cursor: 'pointer',
              transition: 'all 150ms ease',
              userSelect: 'none',
            }}
            title={opt.description}
          >
            <input
              id={radioId}
              type="radio"
              name={`${groupId}-strategy`}
              value={opt.value}
              checked={checked}
              onChange={() => onChange(opt.value)}
              style={{ position: 'absolute', opacity: 0, width: 0, height: 0 }}
            />
            {opt.icon}
            {opt.label}
          </label>
        );
      })}
    </div>
  );
}

// ─── RAM info bar ─────────────────────────────────────────────────────────────

function SystemRamBar({ systemInfo }: { systemInfo: SystemInfo }): React.ReactElement {
  const { totalRamGb, availableRamGb } = systemInfo;
  const usedGb = totalRamGb - availableRamGb;
  const pct = (usedGb / totalRamGb) * 100;

  return (
    <div
      style={{
        padding: '10px 14px',
        borderRadius: '8px',
        background: 'rgba(255,255,255,0.03)',
        border: '1px solid var(--color-border)',
        display: 'flex',
        flexDirection: 'column',
        gap: '6px',
      }}
      aria-label={`System RAM: ${availableRamGb} GB free of ${totalRamGb} GB total`}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>System RAM</span>
        <span style={{ fontSize: '12px', fontWeight: 500, color: 'var(--color-text)' }}>
          {availableRamGb} GB free / {totalRamGb} GB total
        </span>
      </div>
      <div
        role="progressbar"
        aria-valuenow={Math.round(pct)}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={`${usedGb} GB used of ${totalRamGb} GB`}
        style={{
          height: '4px',
          borderRadius: '9999px',
          background: 'rgba(255,255,255,0.08)',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            height: '100%',
            width: `${pct}%`,
            borderRadius: '9999px',
            background:
              pct > 80
                ? 'var(--color-warning)'
                : 'rgba(99,102,241,0.7)',
            transition: 'width 400ms ease',
          }}
        />
      </div>
    </div>
  );
}

// ─── toggle ───────────────────────────────────────────────────────────────────

interface ToggleProps {
  id: string;
  checked: boolean;
  onChange: (v: boolean) => void;
  label: string;
}

function Toggle({ id, checked, onChange, label }: ToggleProps): React.ReactElement {
  return (
    <label
      htmlFor={id}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
        cursor: 'pointer',
        userSelect: 'none',
      }}
    >
      <input
        id={id}
        type="checkbox"
        role="switch"
        aria-checked={checked}
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        style={{ position: 'absolute', opacity: 0, width: 0, height: 0 }}
      />
      {/* visual track */}
      <div
        aria-hidden="true"
        style={{
          width: '42px',
          height: '24px',
          borderRadius: '9999px',
          background: checked ? 'var(--color-primary)' : 'rgba(255,255,255,0.12)',
          border: `1px solid ${checked ? 'var(--color-primary)' : 'rgba(255,255,255,0.18)'}`,
          position: 'relative',
          flexShrink: 0,
          transition: 'background 200ms ease, border-color 200ms ease',
        }}
      >
        <div
          style={{
            position: 'absolute',
            top: '2px',
            left: checked ? '18px' : '2px',
            width: '18px',
            height: '18px',
            borderRadius: '9999px',
            background: '#fff',
            transition: 'left 200ms ease',
            boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
          }}
        />
      </div>
      <span style={{ fontSize: '14px', fontWeight: 600, color: 'var(--color-text)' }}>
        {label}
      </span>
    </label>
  );
}

// ─── main component ────────────────────────────────────────────────────────────

export function ModelPicker(): React.ReactElement {
  const uid = useId();
  const queryClient = useQueryClient();

  const storeSelection = useAppStore((s) => s.settings?.modelSelection);
  const updateModelSelection = useAppStore((s) => s.updateModelSelection);

  const [localSelection, setLocalSelection] = React.useState<ModelSelection>(
    storeSelection ?? { mode: 'auto', modelId: null, autoStrategy: 'balanced' },
  );
  const [pullingIds, setPullingIds] = React.useState<Set<string>>(new Set());

  // sync from store on initial load
  React.useEffect(() => {
    if (storeSelection) setLocalSelection(storeSelection);
  }, [storeSelection]);

  const {
    data: models,
    isLoading: modelsLoading,
    isError: modelsError,
    refetch: refetchModels,
  } = useQuery<OllamaModel[], Error>({
    queryKey: ['models'],
    queryFn: async () => {
      const r = await api.listModels();
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
  });

  const {
    data: systemInfo,
    isLoading: sysLoading,
    isError: sysError,
  } = useQuery<SystemInfo, Error>({
    queryKey: ['system-info'],
    queryFn: async () => {
      const r = await api.getSystemInfo();
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
  });

  const selectionMutation = useMutation<ModelSelection, Error, ModelSelection>({
    mutationFn: async (sel) => {
      const r = await api.setModelSelection(sel);
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
    onSuccess: (saved) => {
      updateModelSelection(saved);
      setLocalSelection(saved);
    },
  });

  const pullMutation = useMutation<{ taskId: string }, Error, string>({
    mutationFn: async (modelId) => {
      const r = await api.pullModel(modelId);
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
    onMutate: (modelId) => {
      setPullingIds((prev) => new Set(prev).add(modelId));
    },
    onSettled: (_data, _err, modelId) => {
      setPullingIds((prev) => {
        const next = new Set(prev);
        next.delete(modelId);
        return next;
      });
      void queryClient.invalidateQueries({ queryKey: ['models'] });
    },
  });

  const applySelection = useCallback(
    (next: ModelSelection) => {
      setLocalSelection(next);
      selectionMutation.mutate(next);
    },
    [selectionMutation],
  );

  const toggleAuto = useCallback(
    (enabled: boolean) => {
      applySelection({
        ...localSelection,
        mode: enabled ? 'auto' : 'manual',
        modelId: enabled ? null : (models?.find((m) => m.isInstalled)?.id ?? null),
      });
    },
    [applySelection, localSelection, models],
  );

  const handleStrategyChange = useCallback(
    (strategy: AutoStrategy) => {
      applySelection({ ...localSelection, autoStrategy: strategy });
    },
    [applySelection, localSelection],
  );

  const handleSelectModel = useCallback(
    (modelId: string) => {
      applySelection({ ...localSelection, mode: 'manual', modelId });
    },
    [applySelection, localSelection],
  );

  const isAutoMode = localSelection.mode === 'auto';

  // current auto-selected model name (best-effort: running model or first installed)
  const autoModel = React.useMemo(
    () =>
      models?.find((m) => m.isRunning)?.displayName ??
      models?.find((m) => m.isInstalled)?.displayName ??
      null,
    [models],
  );

  if (modelsError || sysError) {
    return (
      <EmptyState
        variant="error"
        heading="Could not load models"
        description="Check that the backend is running and try again."
        onRetry={() => void refetchModels()}
      />
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      {/* Auto mode card */}
      <GlassCard style={{ padding: '20px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <Toggle
            id={`${uid}-auto-toggle`}
            checked={isAutoMode}
            onChange={toggleAuto}
            label="Auto"
          />

          <AnimatePresence initial={false}>
            {isAutoMode && (
              <motion.div
                key="auto-section"
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ duration: 0.2, ease: 'easeInOut' }}
                style={{ overflow: 'hidden' }}
              >
                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', paddingTop: '4px' }}>
                  <p style={{ margin: 0, fontSize: '13px', color: 'var(--color-text-muted)' }}>
                    ɳClaw automatically selects the best model for each request.
                  </p>

                  <StrategyPicker
                    groupId={uid}
                    value={localSelection.autoStrategy}
                    onChange={handleStrategyChange}
                  />

                  {autoModel !== null && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>
                        Currently using:
                      </span>
                      <span
                        style={{
                          display: 'inline-flex',
                          alignItems: 'center',
                          padding: '2px 10px',
                          borderRadius: '9999px',
                          fontSize: '12px',
                          fontWeight: 500,
                          background: 'rgba(99,102,241,0.12)',
                          color: 'var(--color-primary-text)',
                          border: '1px solid rgba(99,102,241,0.25)',
                        }}
                        aria-label={`Auto-selected model: ${autoModel}`}
                      >
                        {autoModel}
                      </span>
                    </div>
                  )}

                  {selectionMutation.isPending && (
                    <div
                      style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
                      aria-live="polite"
                    >
                      <Spinner size="sm" aria-label="Saving strategy" />
                      <span style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>
                        Saving…
                      </span>
                    </div>
                  )}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </GlassCard>

      {/* Manual mode section */}
      <AnimatePresence initial={false}>
        {!isAutoMode && (
          <motion.div
            key="manual-section"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            transition={{ duration: 0.2, ease: 'easeOut' }}
          >
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
              {/* RAM info bar */}
              {sysLoading ? (
                <Skeleton variant="rect" height="56px" />
              ) : systemInfo !== undefined ? (
                <SystemRamBar systemInfo={systemInfo} />
              ) : null}

              {/* Model list */}
              <div
                role="radiogroup"
                aria-label="Available models"
                style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}
              >
                {modelsLoading || systemInfo === undefined ? (
                  <ModelListSkeleton />
                ) : models === undefined || models.length === 0 ? (
                  <EmptyState
                    variant="noResults"
                    heading="No models found"
                    description="Pull a model first or check your Ollama installation."
                  />
                ) : (
                  models.map((model) => (
                    <ModelCard
                      key={model.id}
                      model={model}
                      isSelected={localSelection.modelId === model.id}
                      systemInfo={systemInfo}
                      onSelect={handleSelectModel}
                      onPull={(id) => pullMutation.mutate(id)}
                      isPulling={pullingIds.has(model.id)}
                    />
                  ))
                )}
              </div>

              {selectionMutation.isError && (
                <p
                  role="alert"
                  style={{ fontSize: '13px', color: 'var(--color-error)', margin: 0 }}
                >
                  Failed to save selection — {selectionMutation.error?.message ?? 'unknown error'}
                </p>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export default ModelPicker;
