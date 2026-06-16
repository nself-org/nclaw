'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { AnimatePresence, motion } from 'framer-motion';
import { Check, Cpu, Link, Server, Sparkles, User, X } from 'lucide-react';
import type { OnboardingStepId, OllamaModel, PoolAccount } from '@/types';
import { useAppStore } from '@/store/app-store';
import api from '@/lib/api';
import { Button } from '@/components/ui/Button';
import { GlassCard } from '@/components/ui/GlassCard';
import { Input } from '@/components/ui/Input';

// ─── Types ───────────────────────────────────────────────────────────────────

interface WizardState {
  serverUrl: string;
  serverValid: boolean;
  serverChecking: boolean;
  serverError: string | null;
  connectedAccounts: PoolAccount[];
  modelMode: 'auto' | 'manual';
  autoStrategy: 'fastest' | 'balanced' | 'best';
  selectedModelId: string | null;
  models: OllamaModel[];
  displayName: string;
  bio: string;
}

// ─── Step metadata ────────────────────────────────────────────────────────────

const STEPS: OnboardingStepId[] = [
  'welcome',
  'server',
  'oauth',
  'model',
  'profile',
  'preview',
  'done',
];

// ─── Animation variants ───────────────────────────────────────────────────────

const stepVariants = {
  enter: { x: 40, opacity: 0 },
  center: { x: 0, opacity: 1, transition: { duration: 0.28, ease: 'easeOut' } },
  exit: { x: -40, opacity: 0, transition: { duration: 0.2, ease: 'easeIn' } },
};

const checkVariants = {
  hidden: { scale: 0, opacity: 0 },
  visible: (i: number) => ({
    scale: 1,
    opacity: 1,
    transition: { delay: i * 0.12, type: 'spring', stiffness: 400, damping: 20 },
  }),
};

const sparkleVariants = {
  hidden: { scale: 0, opacity: 0 },
  visible: {
    scale: [0, 1.3, 1],
    opacity: [0, 1, 1],
    transition: { duration: 0.5, ease: 'easeOut' },
  },
};

// ─── Provider button data ─────────────────────────────────────────────────────

interface ProviderInfo {
  key: PoolAccount['provider'];
  label: string;
  color: string;
}

const PROVIDERS: ProviderInfo[] = [
  { key: 'google', label: 'Google', color: '#EA4335' },
  { key: 'microsoft', label: 'Microsoft', color: '#00A4EF' },
  { key: 'github', label: 'GitHub', color: '#F0F6FF' },
];

// ─── Shared layout helpers ────────────────────────────────────────────────────

function StepIcon({ children }: { children: React.ReactNode }): React.ReactElement {
  return (
    <div
      style={{
        width: 72,
        height: 72,
        borderRadius: '50%',
        background: 'rgba(99, 102, 241, 0.12)',
        border: '1px solid rgba(99, 102, 241, 0.25)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 24,
        flexShrink: 0,
      }}
    >
      {children}
    </div>
  );
}

function StepHeading({ children }: { children: React.ReactNode }): React.ReactElement {
  return (
    <h2
      style={{
        fontSize: 24,
        fontWeight: 700,
        color: 'var(--color-text)',
        margin: '0 0 12px',
        lineHeight: 1.3,
      }}
    >
      {children}
    </h2>
  );
}

function StepBody({ children }: { children: React.ReactNode }): React.ReactElement {
  return (
    <p
      style={{
        fontSize: 15,
        color: 'var(--color-text-muted)',
        margin: '0 0 28px',
        lineHeight: 1.6,
      }}
    >
      {children}
    </p>
  );
}

// ─── Step components ──────────────────────────────────────────────────────────

interface StepProps {
  state: WizardState;
  setState: React.Dispatch<React.SetStateAction<WizardState>>;
  onNext: () => void;
  onBack: () => void;
}

// Step 1 — Welcome
function WelcomeStep({ onNext }: StepProps): React.ReactElement {
  const router = useRouter();

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
      <div
        style={{
          fontSize: '4rem',
          fontWeight: 900,
          color: 'var(--color-primary-text)',
          lineHeight: 1,
          marginBottom: 24,
          letterSpacing: '-0.02em',
          userSelect: 'none',
        }}
        aria-hidden="true"
      >
        ɳ
      </div>
      <StepHeading>Welcome to ɳClaw</StepHeading>
      <StepBody>
        Your AI assistant with infinite memory. It auto-organises everything you talk about into
        topics — so your knowledge compounds over time.
      </StepBody>
      <Button
        // eslint-disable-next-line jsx-a11y/no-autofocus
        autoFocus
        size="lg"
        onClick={onNext}
        style={{ width: '100%', marginBottom: 16 }}
      >
        Get started →
      </Button>
      <button
        onClick={() => router.push('/login')}
        style={{
          background: 'none',
          border: 'none',
          cursor: 'pointer',
          color: 'var(--color-text-muted)',
          fontSize: 14,
          padding: '4px 8px',
          borderRadius: 4,
          textDecoration: 'underline',
          textUnderlineOffset: 3,
        }}
      >
        Already have an account? Sign in
      </button>
    </div>
  );
}

// Step 2 — Server
function ServerStep({ state, setState, onNext }: StepProps): React.ReactElement {
  const checkServer = useCallback(async (url: string) => {
    if (!url.trim()) return;
    setState((s) => ({ ...s, serverChecking: true, serverError: null }));
    try {
      const probe = await fetch(`${url.replace(/\/$/, '')}/api/claw/system-info`, {
        signal: AbortSignal.timeout(5000),
      });
      if (!probe.ok) throw new Error(`Server returned ${probe.status}`);
      setState((s) => ({ ...s, serverValid: true, serverChecking: false }));
    } catch {
      setState((s) => ({
        ...s,
        serverValid: false,
        serverChecking: false,
        serverError: 'Could not reach server. Please check the URL and try again.',
      }));
    }
  }, [setState]);

  return (
    <div>
      <StepIcon>
        <Server size={28} color="var(--color-primary-text)" />
      </StepIcon>
      <StepHeading>Connect your server</StepHeading>
      <StepBody>
        ɳClaw needs a self-hosted nSelf backend. Enter your server URL below.
      </StepBody>

      <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
        <div style={{ flex: 1 }}>
          <Input
            // eslint-disable-next-line jsx-a11y/no-autofocus
            autoFocus
            label="Server URL"
            placeholder="https://your-server.com"
            value={state.serverUrl}
            onChange={(e) =>
              setState((s) => ({ ...s, serverUrl: e.target.value, serverValid: false, serverError: null }))
            }
            onKeyDown={(e) => {
              if (e.key === 'Enter') checkServer(state.serverUrl);
            }}
            error={state.serverError ?? undefined}
          />
        </div>
        <Button
          variant="outline"
          loading={state.serverChecking}
          onClick={() => checkServer(state.serverUrl)}
          style={{ marginTop: 23, flexShrink: 0 }}
        >
          Auto-detect
        </Button>
      </div>

      {state.serverValid && (
        <p style={{ fontSize: 13, color: 'var(--color-success)', marginBottom: 16, display: 'flex', alignItems: 'center', gap: 6 }}>
          <Check size={14} />
          Server connected successfully
        </p>
      )}

      {state.serverError && !state.serverValid && (
        <p style={{ fontSize: 13, color: 'var(--color-text-muted)', marginBottom: 16 }}>
          Need a server?{' '}
          <a
            href="https://docs.nself.org/getting-started/quick-start"
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: 'var(--color-primary-text)', textDecoration: 'underline', textUnderlineOffset: 3 }}
          >
            Set up a server →
          </a>
        </p>
      )}

      <Button
        size="lg"
        disabled={!state.serverValid}
        onClick={onNext}
        style={{ width: '100%' }}
      >
        Continue →
      </Button>
    </div>
  );
}

// Step 3 — OAuth
function OauthStep({ state, setState, onNext }: StepProps): React.ReactElement {
  const [connecting, setConnecting] = useState<PoolAccount['provider'] | null>(null);

  const handleConnect = useCallback(async (provider: PoolAccount['provider']) => {
    setConnecting(provider);
    const addResult = await api.addPoolAccount(provider);
    if (addResult.ok) {
      window.open(addResult.value.oauthUrl, '_blank', 'noopener,noreferrer,width=600,height=700');
      // Poll for new accounts after a short delay
      await new Promise<void>((r) => setTimeout(r, 2000));
      const accountsResult = await api.listPoolAccounts();
      if (accountsResult.ok) {
        setState((s) => ({ ...s, connectedAccounts: accountsResult.value }));
      }
    }
    // Silent on error — user can retry
    setConnecting(null);
  }, [setState]);

  const isConnected = useCallback(
    (provider: PoolAccount['provider']) =>
      state.connectedAccounts.some((a) => a.provider === provider && a.isActive),
    [state.connectedAccounts]
  );

  return (
    <div>
      <StepIcon>
        <Link size={28} color="var(--color-primary-text)" />
      </StepIcon>
      <StepHeading>Connect your accounts</StepHeading>
      <StepBody>
        Connect Google or other accounts to let ɳClaw access your email and calendar. You can skip
        this.
      </StepBody>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 20 }}>
        {PROVIDERS.map((p, i) => {
          const connected = isConnected(p.key);
          return (
            <button
              key={p.key}
              // eslint-disable-next-line jsx-a11y/no-autofocus
              autoFocus={i === 0}
              disabled={connecting !== null}
              onClick={() => handleConnect(p.key)}
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                padding: '12px 16px',
                borderRadius: 10,
                border: `1px solid ${connected ? 'rgba(74,222,128,0.35)' : 'var(--color-border)'}`,
                background: connected ? 'rgba(74,222,128,0.06)' : 'var(--color-bg-card)',
                cursor: connecting !== null ? 'not-allowed' : 'pointer',
                color: 'var(--color-text)',
                fontSize: 14,
                fontWeight: 500,
                opacity: connecting !== null && connecting !== p.key ? 0.5 : 1,
                transition: 'all var(--transition-fast)',
              }}
            >
              <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span
                  style={{
                    width: 10,
                    height: 10,
                    borderRadius: '50%',
                    background: p.color,
                    flexShrink: 0,
                  }}
                />
                {p.label}
              </span>
              {connected ? (
                <span style={{ display: 'flex', alignItems: 'center', gap: 4, color: 'var(--color-success)', fontSize: 13 }}>
                  <Check size={14} />
                  Connected
                </span>
              ) : connecting === p.key ? (
                <span style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>Connecting…</span>
              ) : (
                <span style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>Connect</span>
              )}
            </button>
          );
        })}
      </div>

      {state.connectedAccounts.length > 0 && (
        <div style={{ marginBottom: 20 }}>
          <p style={{ fontSize: 12, color: 'var(--color-text-muted)', marginBottom: 8, fontWeight: 500 }}>
            CONNECTED
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {state.connectedAccounts.map((acc) => (
              <div
                key={acc.id}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  padding: '8px 12px',
                  borderRadius: 8,
                  background: 'rgba(255,255,255,0.04)',
                  fontSize: 13,
                  color: 'var(--color-text-muted)',
                }}
              >
                <span
                  style={{
                    width: 8,
                    height: 8,
                    borderRadius: '50%',
                    background: PROVIDERS.find((p) => p.key === acc.provider)?.color ?? '#888',
                    flexShrink: 0,
                  }}
                />
                <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {acc.email}
                </span>
                <Check size={14} color="var(--color-success)" />
              </div>
            ))}
          </div>
        </div>
      )}

      <Button size="lg" onClick={onNext} style={{ width: '100%', marginBottom: 12 }}>
        Continue →
      </Button>
      <div style={{ textAlign: 'center' }}>
        <button
          onClick={onNext}
          style={{
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            color: 'var(--color-text-muted)',
            fontSize: 14,
            padding: '4px 8px',
            borderRadius: 4,
            textDecoration: 'underline',
            textUnderlineOffset: 3,
          }}
        >
          Skip for now
        </button>
      </div>
    </div>
  );
}

// Step 4 — Model
function ModelStep({ state, setState, onNext }: StepProps): React.ReactElement {
  const [showAll, setShowAll] = useState(false);

  return (
    <div>
      <StepIcon>
        <Cpu size={28} color="var(--color-primary-text)" />
      </StepIcon>
      <StepHeading>Choose your AI model</StepHeading>
      <StepBody>
        Select how ɳClaw picks the AI model. Auto mode is recommended.
      </StepBody>

      {/* Auto toggle */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '14px 16px',
          borderRadius: 10,
          border: `1px solid ${state.modelMode === 'auto' ? 'rgba(99,102,241,0.4)' : 'var(--color-border)'}`,
          background: state.modelMode === 'auto' ? 'rgba(99,102,241,0.08)' : 'var(--color-bg-card)',
          marginBottom: 12,
          cursor: 'pointer',
        }}
        role="button"
        tabIndex={0}
        // eslint-disable-next-line jsx-a11y/no-autofocus
        autoFocus
        aria-pressed={state.modelMode === 'auto'}
        onClick={() => setState((s) => ({ ...s, modelMode: 'auto' }))}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') setState((s) => ({ ...s, modelMode: 'auto' }));
        }}
      >
        <div>
          <p style={{ margin: 0, fontWeight: 600, fontSize: 14, color: 'var(--color-text)' }}>
            Auto (recommended)
          </p>
          <p style={{ margin: '2px 0 0', fontSize: 13, color: 'var(--color-text-muted)' }}>
            ɳClaw picks the best available model
          </p>
        </div>
        <div
          style={{
            width: 20,
            height: 20,
            borderRadius: '50%',
            border: `2px solid ${state.modelMode === 'auto' ? 'var(--color-primary)' : 'var(--color-border)'}`,
            background: state.modelMode === 'auto' ? 'var(--color-primary)' : 'transparent',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          {state.modelMode === 'auto' && <Check size={11} color="#fff" strokeWidth={3} />}
        </div>
      </div>

      {/* Auto strategy — only shown in auto mode */}
      {state.modelMode === 'auto' && (
        <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
          {(['fastest', 'balanced', 'best'] as const).map((strategy) => (
            <button
              key={strategy}
              onClick={() => setState((s) => ({ ...s, autoStrategy: strategy }))}
              style={{
                flex: 1,
                padding: '8px 4px',
                borderRadius: 8,
                border: `1px solid ${state.autoStrategy === strategy ? 'var(--color-primary)' : 'var(--color-border)'}`,
                background: state.autoStrategy === strategy ? 'rgba(99,102,241,0.15)' : 'transparent',
                color: state.autoStrategy === strategy ? 'var(--color-primary-text)' : 'var(--color-text-muted)',
                fontSize: 13,
                fontWeight: state.autoStrategy === strategy ? 600 : 400,
                cursor: 'pointer',
                textTransform: 'capitalize',
                transition: 'all var(--transition-fast)',
              }}
            >
              {strategy}
            </button>
          ))}
        </div>
      )}

      {/* Manual toggle */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '14px 16px',
          borderRadius: 10,
          border: `1px solid ${state.modelMode === 'manual' ? 'rgba(99,102,241,0.4)' : 'var(--color-border)'}`,
          background: state.modelMode === 'manual' ? 'rgba(99,102,241,0.08)' : 'var(--color-bg-card)',
          marginBottom: 16,
          cursor: 'pointer',
        }}
        role="button"
        tabIndex={0}
        aria-pressed={state.modelMode === 'manual'}
        onClick={() => setState((s) => ({ ...s, modelMode: 'manual' }))}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') setState((s) => ({ ...s, modelMode: 'manual' }));
        }}
      >
        <div>
          <p style={{ margin: 0, fontWeight: 600, fontSize: 14, color: 'var(--color-text)' }}>
            Manual
          </p>
          <p style={{ margin: '2px 0 0', fontSize: 13, color: 'var(--color-text-muted)' }}>
            You pick the model each time
          </p>
        </div>
        <div
          style={{
            width: 20,
            height: 20,
            borderRadius: '50%',
            border: `2px solid ${state.modelMode === 'manual' ? 'var(--color-primary)' : 'var(--color-border)'}`,
            background: state.modelMode === 'manual' ? 'var(--color-primary)' : 'transparent',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          {state.modelMode === 'manual' && <Check size={11} color="#fff" strokeWidth={3} />}
        </div>
      </div>

      {/* Show all models toggle */}
      {state.modelMode === 'manual' && (
        <div style={{ marginBottom: 16 }}>
          <button
            onClick={() => setShowAll((v) => !v)}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--color-primary-text)',
              fontSize: 14,
              padding: 0,
              textDecoration: 'underline',
              textUnderlineOffset: 3,
            }}
          >
            {showAll ? 'Hide models' : 'Show all models'}
          </button>

          {showAll && state.models.length > 0 && (
            <div
              style={{
                marginTop: 10,
                maxHeight: 200,
                overflowY: 'auto',
                display: 'flex',
                flexDirection: 'column',
                gap: 6,
              }}
            >
              {state.models.map((m) => (
                <button
                  key={m.id}
                  onClick={() => setState((s) => ({ ...s, selectedModelId: m.id }))}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '8px 12px',
                    borderRadius: 8,
                    border: `1px solid ${state.selectedModelId === m.id ? 'var(--color-primary)' : 'var(--color-border)'}`,
                    background: state.selectedModelId === m.id ? 'rgba(99,102,241,0.1)' : 'transparent',
                    cursor: 'pointer',
                    fontSize: 13,
                    color: 'var(--color-text)',
                    textAlign: 'left',
                  }}
                >
                  <span>{m.displayName}</span>
                  {m.isInstalled && (
                    <span style={{ fontSize: 11, color: 'var(--color-success)', fontWeight: 600 }}>Installed</span>
                  )}
                </button>
              ))}
            </div>
          )}

          {showAll && state.models.length === 0 && (
            <p style={{ fontSize: 13, color: 'var(--color-text-muted)', marginTop: 8 }}>
              No models found. Make sure Ollama is running on your server.
            </p>
          )}
        </div>
      )}

      <Button size="lg" onClick={onNext} style={{ width: '100%' }}>
        Continue →
      </Button>
    </div>
  );
}

// Step 5 — Profile
function ProfileStep({ state, setState, onNext }: StepProps): React.ReactElement {
  return (
    <div>
      <StepIcon>
        <User size={28} color="var(--color-primary-text)" />
      </StepIcon>
      <StepHeading>What should we call you?</StepHeading>
      <StepBody>
        Give ɳClaw a name for you. You can add a profile photo in Settings later.
      </StepBody>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginBottom: 28 }}>
        <Input
          // eslint-disable-next-line jsx-a11y/no-autofocus
          autoFocus
          label="Display name"
          placeholder="Your name"
          value={state.displayName}
          onChange={(e) => setState((s) => ({ ...s, displayName: e.target.value }))}
        />

        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <label
            style={{
              fontSize: 13,
              fontWeight: 500,
              color: 'var(--color-text-muted)',
            }}
          >
            Bio
          </label>
          <textarea
            placeholder="A bit about yourself… (optional)"
            value={state.bio}
            rows={3}
            onChange={(e) => setState((s) => ({ ...s, bio: e.target.value }))}
            style={{
              background: 'var(--color-bg-input)',
              border: '1px solid var(--color-border)',
              borderRadius: 8,
              padding: '10px 12px',
              color: 'var(--color-text)',
              fontSize: 14,
              resize: 'vertical',
              outline: 'none',
              lineHeight: 1.5,
              fontFamily: 'inherit',
              transition: 'border-color var(--transition-fast)',
            }}
            onFocus={(e) => {
              (e.target as HTMLTextAreaElement).style.borderColor = 'var(--color-border-focus)';
              (e.target as HTMLTextAreaElement).style.boxShadow = '0 0 0 3px var(--color-border-focus)';
            }}
            onBlur={(e) => {
              (e.target as HTMLTextAreaElement).style.borderColor = 'var(--color-border)';
              (e.target as HTMLTextAreaElement).style.boxShadow = 'none';
            }}
          />
        </div>
      </div>

      <Button size="lg" onClick={onNext} style={{ width: '100%' }}>
        Continue →
      </Button>
    </div>
  );
}

// Step 6 — Preview
interface PreviewRow {
  label: string;
  value: string;
  ok: boolean;
}

function PreviewStep({ state, onNext }: StepProps): React.ReactElement {
  const rows: PreviewRow[] = [
    {
      label: 'Server',
      value: state.serverValid ? state.serverUrl : 'Not connected',
      ok: state.serverValid,
    },
    {
      label: 'Accounts',
      value:
        state.connectedAccounts.length > 0
          ? `${state.connectedAccounts.length} connected`
          : 'None connected',
      ok: state.connectedAccounts.length > 0,
    },
    {
      label: 'Model',
      value:
        state.modelMode === 'auto'
          ? `Auto / ${state.autoStrategy}`
          : state.selectedModelId ?? 'Manual (none selected)',
      ok: true,
    },
    {
      label: 'Name',
      value: state.displayName.trim() || 'Not set',
      ok: state.displayName.trim().length > 0,
    },
  ];

  return (
    <div>
      <h2
        style={{
          fontSize: 24,
          fontWeight: 700,
          color: 'var(--color-text)',
          margin: '0 0 24px',
          lineHeight: 1.3,
        }}
      >
        You're almost ready
      </h2>

      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          gap: 10,
          marginBottom: 32,
        }}
      >
        {rows.map((row, i) => (
          <motion.div
            key={row.label}
            custom={i}
            variants={checkVariants}
            initial="hidden"
            animate="visible"
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '12px 16px',
              borderRadius: 10,
              background: 'var(--color-bg-card)',
              border: '1px solid var(--color-border)',
            }}
          >
            <div>
              <p style={{ margin: 0, fontSize: 12, color: 'var(--color-text-muted)', fontWeight: 500 }}>
                {row.label.toUpperCase()}
              </p>
              <p
                style={{
                  margin: '2px 0 0',
                  fontSize: 14,
                  color: 'var(--color-text)',
                  wordBreak: 'break-all',
                }}
              >
                {row.value}
              </p>
            </div>
            <div
              style={{
                width: 28,
                height: 28,
                borderRadius: '50%',
                background: row.ok ? 'rgba(74,222,128,0.15)' : 'rgba(248,113,113,0.12)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                flexShrink: 0,
              }}
            >
              {row.ok ? (
                <Check size={14} color="var(--color-success)" strokeWidth={2.5} />
              ) : (
                <X size={14} color="var(--color-error)" strokeWidth={2.5} />
              )}
            </div>
          </motion.div>
        ))}
      </div>

      <Button
        // eslint-disable-next-line jsx-a11y/no-autofocus
        autoFocus
        size="lg"
        onClick={onNext}
        style={{ width: '100%' }}
      >
        Start using ɳClaw →
      </Button>
    </div>
  );
}

// Step 7 — Done
function DoneStep(): React.ReactElement {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '32px 0' }}>
      <motion.div
        variants={sparkleVariants}
        initial="hidden"
        animate="visible"
        style={{
          width: 80,
          height: 80,
          borderRadius: '50%',
          background: 'rgba(99,102,241,0.15)',
          border: '1px solid rgba(99,102,241,0.3)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          marginBottom: 20,
        }}
      >
        <Sparkles size={36} color="var(--color-primary-text)" />
      </motion.div>
      <p style={{ fontSize: 18, fontWeight: 600, color: 'var(--color-text)', margin: 0 }}>
        Setting up your workspace…
      </p>
    </div>
  );
}

// ─── Progress bar ─────────────────────────────────────────────────────────────

function ProgressBar({ stepIndex, total }: { stepIndex: number; total: number }): React.ReactElement {
  // Don't show progress on welcome or done
  if (stepIndex === 0 || stepIndex === total - 1) return <div style={{ height: 4 }} />;

  const visibleTotal = total - 2; // exclude welcome and done
  const visibleIndex = stepIndex - 1; // 0-based for visible steps

  return (
    <div style={{ padding: '0 0 24px' }}>
      <div style={{ display: 'flex', gap: 4, marginBottom: 8 }}>
        {Array.from({ length: visibleTotal }, (_, i) => (
          <div
            key={i}
            style={{
              flex: 1,
              height: 3,
              borderRadius: 99,
              background:
                i < visibleIndex
                  ? 'var(--color-primary)'
                  : i === visibleIndex
                  ? 'rgba(99,102,241,0.6)'
                  : 'var(--color-border)',
              transition: 'background var(--transition-base)',
            }}
          />
        ))}
      </div>
      <p style={{ margin: 0, fontSize: 12, color: 'var(--color-text-muted)' }}>
        Step {visibleIndex + 1} of {visibleTotal}
      </p>
    </div>
  );
}

// ─── Main wizard ──────────────────────────────────────────────────────────────

export function OnboardingWizard(): React.ReactElement {
  const router = useRouter();
  const { setOnboardingComplete, setOnboardingStep, updateModelSelection, setSettings, settings } =
    useAppStore();

  const [stepIndex, setStepIndex] = useState(0);
  const [direction, setDirection] = useState<'forward' | 'back'>('forward');

  const [wizardState, setWizardState] = useState<WizardState>({
    serverUrl: '',
    serverValid: false,
    serverChecking: false,
    serverError: null,
    connectedAccounts: [],
    modelMode: 'auto',
    autoStrategy: 'balanced',
    selectedModelId: null,
    models: [],
    displayName: '',
    bio: '',
  });

  const currentStepId = STEPS[stepIndex];

  // Fetch models when reaching model step
  useEffect(() => {
    if (currentStepId === 'model' && wizardState.serverValid) {
      void api.listModels().then((r) => {
        if (r.ok) setWizardState((s) => ({ ...s, models: r.value }));
      });
    }
  }, [currentStepId, wizardState.serverValid]);

  // Sync step to store
  useEffect(() => {
    setOnboardingStep(currentStepId);
  }, [currentStepId, setOnboardingStep]);

  // Auto-navigate from done step
  useEffect(() => {
    if (currentStepId !== 'done') return;

    const commitAndNavigate = async () => {
      // Persist model selection
      const newSel = {
        mode: wizardState.modelMode,
        modelId: wizardState.modelMode === 'manual' ? wizardState.selectedModelId : null,
        autoStrategy: wizardState.autoStrategy,
      };
      updateModelSelection(newSel);

      // Persist display name + bio
      if (wizardState.displayName.trim()) {
        // Non-fatal — user can update in Settings
        await api.updateMe({
          displayName: wizardState.displayName.trim(),
          bio: wizardState.bio.trim() || null,
        });
      }

      // Persist settings
      const updatedSettings = {
        ...(settings ?? {
          displayName: null,
          bio: null,
          avatarUrl: null,
          notificationsEnabled: true,
          compactMode: false,
          language: 'en',
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          dataRetentionDays: null,
          autoTitleSessions: true,
          emailDigestEnabled: false,
        }),
        modelSelection: newSel,
        displayName: wizardState.displayName.trim() || null,
        bio: wizardState.bio.trim() || null,
      };
      setSettings(updatedSettings);
      setOnboardingComplete(true);
      router.push('/');
    };

    const timer = setTimeout(commitAndNavigate, 1000);
    return () => clearTimeout(timer);
  }, [
    currentStepId,
    wizardState,
    settings,
    router,
    setOnboardingComplete,
    updateModelSelection,
    setSettings,
  ]);

  const goNext = useCallback(() => {
    if (stepIndex >= STEPS.length - 1) return;
    setDirection('forward');
    setStepIndex((i) => i + 1);
  }, [stepIndex]);

  const goBack = useCallback(() => {
    if (stepIndex <= 0) return;
    setDirection('back');
    setStepIndex((i) => i - 1);
  }, [stepIndex]);

  // Keyboard navigation
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && stepIndex > 0 && currentStepId !== 'done') {
        goBack();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [stepIndex, currentStepId, goBack]);

  const stepProps: StepProps = {
    state: wizardState,
    setState: setWizardState,
    onNext: goNext,
    onBack: goBack,
  };

  const renderStep = (): React.ReactElement => {
    switch (currentStepId) {
      case 'welcome': return <WelcomeStep {...stepProps} />;
      case 'server':  return <ServerStep {...stepProps} />;
      case 'oauth':   return <OauthStep {...stepProps} />;
      case 'model':   return <ModelStep {...stepProps} />;
      case 'profile': return <ProfileStep {...stepProps} />;
      case 'preview': return <PreviewStep {...stepProps} />;
      case 'done':    return <DoneStep />;
    }
  };

  const enterX = direction === 'forward' ? 40 : -40;
  const exitX  = direction === 'forward' ? -40 : 40;

  return (
    <div
      style={{
        minHeight: '100vh',
        background: 'var(--color-bg)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 24,
      }}
      role="main"
      aria-label="Onboarding wizard"
    >
      <GlassCard
        variant="modal"
        style={{
          width: '100%',
          maxWidth: 480,
          padding: '32px 36px',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        {/* Back button */}
        {stepIndex > 0 && currentStepId !== 'done' && (
          <button
            onClick={goBack}
            aria-label="Go back"
            style={{
              position: 'absolute',
              top: 20,
              left: 20,
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--color-text-muted)',
              padding: '4px 8px',
              borderRadius: 6,
              fontSize: 22,
              lineHeight: 1,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            ←
          </button>
        )}

        <ProgressBar stepIndex={stepIndex} total={STEPS.length} />

        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={currentStepId}
            variants={{
              enter: { x: enterX, opacity: 0 },
              center: stepVariants.center,
              exit: { x: exitX, opacity: 0, transition: stepVariants.exit.transition },
            }}
            initial="enter"
            animate="center"
            exit="exit"
          >
            {renderStep()}
          </motion.div>
        </AnimatePresence>
      </GlassCard>
    </div>
  );
}

export default OnboardingWizard;
