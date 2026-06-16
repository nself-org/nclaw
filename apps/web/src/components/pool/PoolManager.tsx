'use client';

import React, { useCallback, useEffect, useRef, useId } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Plus,
  RotateCw,
  Trash2,
  Chrome,
  Github,
  Monitor,
  Globe,
} from 'lucide-react';
import { GlassCard } from '@/components/ui/GlassCard';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Spinner } from '@/components/ui/Spinner';
import { EmptyState } from '@/components/ui/EmptyState';
import api from '@/lib/api';
import type { PoolAccount } from '@/types';

// ─── helpers ─────────────────────────────────────────────────────────────────

function formatRelativeTime(iso: string | null): string {
  if (!iso) return 'Never used';
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `Last used ${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `Last used ${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `Last used ${days}d ago`;
}

function isExpiringSoon(expiresAt: string | null): boolean {
  if (!expiresAt) return false;
  const diff = new Date(expiresAt).getTime() - Date.now();
  return diff > 0 && diff < 7 * 24 * 60 * 60 * 1000; // within 7 days
}

function isExpired(expiresAt: string | null): boolean {
  if (!expiresAt) return false;
  return new Date(expiresAt).getTime() < Date.now();
}

// ─── provider icon / label ────────────────────────────────────────────────────

interface ProviderInfo {
  label: string;
  icon: React.ReactNode;
  color: string;
}

const PROVIDER_INFO: Record<PoolAccount['provider'], ProviderInfo> = {
  google: {
    label: 'Google',
    icon: <Chrome size={16} aria-hidden="true" />,
    color: '#EA4335',
  },
  microsoft: {
    label: 'Microsoft',
    icon: <Monitor size={16} aria-hidden="true" />,
    color: '#00A1F1',
  },
  github: {
    label: 'GitHub',
    icon: <Github size={16} aria-hidden="true" />,
    color: '#F0F6FC',
  },
  custom: {
    label: 'Custom',
    icon: <Globe size={16} aria-hidden="true" />,
    color: 'var(--color-text-muted)',
  },
};

// ─── scope badge list ─────────────────────────────────────────────────────────

function ScopeList({ scopes }: { scopes: string[] }): React.ReactElement {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
      {scopes.map((s) => (
        <Badge key={s} variant="default" style={{ fontSize: '11px', padding: '1px 7px' }}>
          {s}
        </Badge>
      ))}
    </div>
  );
}

// ─── status indicator ─────────────────────────────────────────────────────────

interface StatusDotProps {
  account: PoolAccount;
}

function StatusDot({ account }: StatusDotProps): React.ReactElement {
  const expired = isExpired(account.expiresAt);
  const expiringSoon = !expired && isExpiringSoon(account.expiresAt);

  const color = expired
    ? 'var(--color-error)'
    : expiringSoon
    ? 'var(--color-warning)'
    : 'var(--color-success)';

  const label = expired ? 'Expired' : expiringSoon ? 'Token expiring soon' : 'Active';
  const badgeVariant = expired ? 'error' : expiringSoon ? 'warning' : 'success';

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
      <div
        aria-hidden="true"
        style={{
          width: '7px',
          height: '7px',
          borderRadius: '9999px',
          background: color,
          flexShrink: 0,
        }}
      />
      <Badge variant={badgeVariant}>{label}</Badge>
    </div>
  );
}

// ─── remove confirmation ──────────────────────────────────────────────────────

interface RemoveConfirmProps {
  account: PoolAccount;
  routingRuleCount: number;
  onConfirm: () => void;
  onCancel: () => void;
  isPending: boolean;
}

function RemoveConfirm({
  account,
  routingRuleCount,
  onConfirm,
  onCancel,
  isPending,
}: RemoveConfirmProps): React.ReactElement {
  // auto-focus the confirm zone for keyboard accessibility
  const confirmZoneRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // focus the first focusable child inside the confirm zone
    const btn = confirmZoneRef.current?.querySelector<HTMLElement>('button');
    btn?.focus();
  }, []);

  return (
    <motion.div
      initial={{ opacity: 0, height: 0 }}
      animate={{ opacity: 1, height: 'auto' }}
      exit={{ opacity: 0, height: 0 }}
      transition={{ duration: 0.15, ease: 'easeInOut' }}
      style={{ overflow: 'hidden' }}
    >
      <div
        style={{
          paddingTop: '10px',
          borderTop: '1px solid var(--color-border)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '12px',
          flexWrap: 'wrap',
        }}
        role="group"
        aria-label={`Confirm removal of ${account.email}`}
      >
        <p style={{ margin: 0, fontSize: '13px', color: 'var(--color-text-muted)' }}>
          Remove <strong style={{ color: 'var(--color-text)' }}>{account.email}</strong>?
          {routingRuleCount > 0 && (
            <> This will affect {routingRuleCount} routing rule{routingRuleCount !== 1 ? 's' : ''}.</>
          )}
        </p>
        <div ref={confirmZoneRef} style={{ display: 'flex', gap: '8px', flexShrink: 0 }}>
          <Button variant="ghost" size="sm" onClick={onCancel} disabled={isPending}>
            Cancel
          </Button>
          <Button
            variant="danger"
            size="sm"
            loading={isPending}
            onClick={onConfirm}
            aria-label={`Confirm remove ${account.email}`}
          >
            Remove
          </Button>
        </div>
      </div>
    </motion.div>
  );
}

// ─── account card ─────────────────────────────────────────────────────────────

interface AccountCardProps {
  account: PoolAccount;
  onRemoved: () => void;
}

function AccountCard({ account, onRemoved }: AccountCardProps): React.ReactElement {
  const [confirmingRemove, setConfirmingRemove] = React.useState(false);
  const [refreshSuccess, setRefreshSuccess] = React.useState(false);
  const [refreshError, setRefreshError] = React.useState<string | null>(null);
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const removeMutation = useMutation<void, Error>({
    mutationFn: async () => {
      const r = await api.removePoolAccount(account.id);
      if (!r.ok) throw new Error(r.error.message);
    },
    onSuccess: () => {
      onRemoved();
    },
  });

  const refreshMutation = useMutation<PoolAccount, Error>({
    mutationFn: async () => {
      const r = await api.refreshPoolAccount(account.id);
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
    onSuccess: () => {
      setRefreshSuccess(true);
      setRefreshError(null);
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
      refreshTimerRef.current = setTimeout(() => setRefreshSuccess(false), 3000);
    },
    onError: (err) => {
      setRefreshError(err.message ?? 'Refresh failed');
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
      refreshTimerRef.current = setTimeout(() => setRefreshError(null), 5000);
    },
  });

  useEffect(() => {
    return () => {
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
    };
  }, []);

  const providerInfo = PROVIDER_INFO[account.provider];

  return (
    <GlassCard style={{ padding: '16px' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {/* Provider + email header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'flex-start',
            justifyContent: 'space-between',
            gap: '12px',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', minWidth: 0 }}>
            <div
              aria-hidden="true"
              style={{
                color: providerInfo.color,
                display: 'flex',
                alignItems: 'center',
                flexShrink: 0,
              }}
            >
              {providerInfo.icon}
            </div>
            <div style={{ minWidth: 0 }}>
              <p
                style={{
                  margin: 0,
                  fontSize: '14px',
                  fontWeight: 600,
                  color: 'var(--color-text)',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {account.email}
              </p>
              <p style={{ margin: '2px 0 0', fontSize: '12px', color: 'var(--color-text-muted)' }}>
                {providerInfo.label}
              </p>
            </div>
          </div>
          <StatusDot account={account} />
        </div>

        {/* Scopes */}
        {account.scopes.length > 0 && <ScopeList scopes={account.scopes} />}

        {/* Last used */}
        <p style={{ margin: 0, fontSize: '12px', color: 'var(--color-text-muted)' }}>
          {formatRelativeTime(account.lastUsedAt)}
        </p>

        {/* Actions row */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            justifyContent: 'flex-end',
            flexWrap: 'wrap',
          }}
        >
          {refreshSuccess && (
            <span
              role="status"
              aria-live="polite"
              style={{ fontSize: '12px', color: 'var(--color-success)', marginRight: 'auto' }}
            >
              Token refreshed
            </span>
          )}
          {refreshError !== null && (
            <span
              role="alert"
              aria-live="polite"
              style={{ fontSize: '12px', color: 'var(--color-error)', marginRight: 'auto' }}
            >
              {refreshError}
            </span>
          )}

          <Button
            variant="outline"
            size="sm"
            loading={refreshMutation.isPending}
            onClick={() => refreshMutation.mutate()}
            aria-label={`Refresh token for ${account.email}`}
          >
            {!refreshMutation.isPending && <RotateCw size={13} aria-hidden="true" />}
            Refresh token
          </Button>

          <Button
            variant="danger"
            size="sm"
            onClick={() => setConfirmingRemove(true)}
            aria-label={`Remove account ${account.email}`}
            disabled={removeMutation.isPending || confirmingRemove}
          >
            <Trash2 size={13} aria-hidden="true" />
            Remove
          </Button>
        </div>

        {/* Inline remove confirmation */}
        <AnimatePresence initial={false}>
          {confirmingRemove && (
            <RemoveConfirm
              key="confirm"
              account={account}
              routingRuleCount={0}
              onConfirm={() => removeMutation.mutate()}
              onCancel={() => setConfirmingRemove(false)}
              isPending={removeMutation.isPending}
            />
          )}
        </AnimatePresence>
      </div>
    </GlassCard>
  );
}

// ─── add account modal ────────────────────────────────────────────────────────

type Provider = PoolAccount['provider'];

interface ProviderButtonProps {
  provider: Provider;
  onClick: () => void;
}

function ProviderButton({ provider, onClick }: ProviderButtonProps): React.ReactElement {
  const info = PROVIDER_INFO[provider];
  const [hovered, setHovered] = React.useState(false);

  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
        width: '100%',
        padding: '12px 16px',
        borderRadius: '8px',
        border: `1px solid ${hovered ? 'rgba(255,255,255,0.18)' : 'var(--color-border)'}`,
        background: hovered ? 'rgba(255,255,255,0.04)' : 'transparent',
        color: 'var(--color-text)',
        fontSize: '14px',
        fontWeight: 500,
        cursor: 'pointer',
        transition: 'border-color 150ms ease, background 150ms ease',
        textAlign: 'left',
      }}
      aria-label={`Add ${info.label} account`}
    >
      <span style={{ color: info.color, display: 'flex', alignItems: 'center' }}>
        {info.icon}
      </span>
      {info.label}
    </button>
  );
}

const PROVIDERS: Provider[] = ['google', 'microsoft', 'github', 'custom'];
const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 120_000;

interface AddAccountModalProps {
  onClose: () => void;
  onAdded: () => void;
}

function AddAccountModal({ onClose, onAdded }: AddAccountModalProps): React.ReactElement {
  const uid = useId();
  const overlayRef = useRef<HTMLDivElement>(null);
  const [phase, setPhase] = React.useState<'pick' | 'waiting'>('pick');
  const [error, setError] = React.useState<string | null>(null);
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const timeoutTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // focus trap
  const firstFocusableRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    firstFocusableRef.current?.focus();
    return () => {
      if (pollTimerRef.current) clearInterval(pollTimerRef.current);
      if (timeoutTimerRef.current) clearTimeout(timeoutTimerRef.current);
    };
  }, []);

  const stopPolling = useCallback(() => {
    if (pollTimerRef.current) clearInterval(pollTimerRef.current);
    if (timeoutTimerRef.current) clearTimeout(timeoutTimerRef.current);
  }, []);

  const addMutation = useMutation<{ oauthUrl: string }, Error, Provider>({
    mutationFn: async (provider) => {
      const r = await api.addPoolAccount(provider);
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
    onSuccess: ({ oauthUrl }) => {
      window.open(oauthUrl, '_blank', 'noopener,noreferrer');
      setPhase('waiting');

      // poll for new account — capture initial count first
      void api.listPoolAccounts().then((initial) => {
        if (!initial.ok) return;
        const initialCount = initial.value.length;

        pollTimerRef.current = setInterval(() => {
          void api.listPoolAccounts().then((current) => {
            if (current.ok && current.value.length > initialCount) {
              stopPolling();
              onAdded();
            }
          });
        }, POLL_INTERVAL_MS);

        timeoutTimerRef.current = setTimeout(() => {
          stopPolling();
          setError('Authorization timed out. Please try again.');
          setPhase('pick');
        }, POLL_TIMEOUT_MS);
      });
    },
    onError: (err) => {
      setError(err.message ?? 'Failed to start OAuth flow');
    },
  });

  const handleOverlayClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (e.target === overlayRef.current) onClose();
    },
    [onClose],
  );

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (e.key === 'Escape') onClose();
    },
    [onClose],
  );

  return (
    <div
      ref={overlayRef}
      role="dialog"
      aria-modal="true"
      aria-labelledby={`${uid}-modal-title`}
      onKeyDown={handleKeyDown}
      onClick={handleOverlayClick}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.6)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '24px',
        zIndex: 100,
      }}
    >
      <GlassCard
        variant="modal"
        style={{ width: '100%', maxWidth: '400px', padding: '24px' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
            }}
          >
            <h2
              id={`${uid}-modal-title`}
              style={{ margin: 0, fontSize: '16px', fontWeight: 600, color: 'var(--color-text)' }}
            >
              Add account
            </h2>
            <button
              ref={firstFocusableRef}
              type="button"
              onClick={onClose}
              aria-label="Close add account dialog"
              style={{
                background: 'transparent',
                border: 'none',
                cursor: 'pointer',
                color: 'var(--color-text-muted)',
                fontSize: '18px',
                lineHeight: 1,
                padding: '4px',
                borderRadius: '4px',
              }}
            >
              ×
            </button>
          </div>

          {phase === 'pick' && (
            <>
              <p style={{ margin: 0, fontSize: '13px', color: 'var(--color-text-muted)' }}>
                Choose a provider to connect.
              </p>

              {error !== null && (
                <p
                  role="alert"
                  style={{ margin: 0, fontSize: '13px', color: 'var(--color-error)' }}
                >
                  {error}
                </p>
              )}

              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {PROVIDERS.map((p) => (
                  <ProviderButton
                    key={p}
                    provider={p}
                    onClick={() => addMutation.mutate(p)}
                  />
                ))}
              </div>

              {addMutation.isPending && (
                <div style={{ display: 'flex', justifyContent: 'center' }}>
                  <Spinner size="sm" aria-label="Starting OAuth flow" />
                </div>
              )}
            </>
          )}

          {phase === 'waiting' && (
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: '16px',
                padding: '16px 0',
              }}
            >
              <Spinner size="md" aria-label="Waiting for authorization" />
              <p
                style={{
                  margin: 0,
                  fontSize: '14px',
                  color: 'var(--color-text-muted)',
                  textAlign: 'center',
                }}
              >
                Complete authorization in the popup window…
              </p>
              <Button variant="ghost" size="sm" onClick={onClose}>
                Cancel
              </Button>
            </div>
          )}
        </div>
      </GlassCard>
    </div>
  );
}

// ─── main component ────────────────────────────────────────────────────────────

export function PoolManager(): React.ReactElement {
  const queryClient = useQueryClient();
  const [showAddModal, setShowAddModal] = React.useState(false);
  const [addedMessage, setAddedMessage] = React.useState<string | null>(null);
  const addedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const {
    data: accounts,
    isLoading,
    isError,
    refetch,
  } = useQuery<PoolAccount[], Error>({
    queryKey: ['pool-accounts'],
    queryFn: async () => {
      const r = await api.listPoolAccounts();
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
  });

  useEffect(() => {
    return () => {
      if (addedTimerRef.current) clearTimeout(addedTimerRef.current);
    };
  }, []);

  const handleAdded = useCallback(() => {
    setShowAddModal(false);
    void queryClient.invalidateQueries({ queryKey: ['pool-accounts'] });
    setAddedMessage('Account connected successfully');
    if (addedTimerRef.current) clearTimeout(addedTimerRef.current);
    addedTimerRef.current = setTimeout(() => setAddedMessage(null), 4000);
  }, [queryClient]);

  const handleRemoved = useCallback(() => {
    void queryClient.invalidateQueries({ queryKey: ['pool-accounts'] });
  }, [queryClient]);

  if (isError) {
    return (
      <EmptyState
        variant="error"
        heading="Could not load accounts"
        description="Check your connection and try again."
        onRetry={() => void refetch()}
      />
    );
  }

  return (
    <>
      <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
        {/* Header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '12px',
            flexWrap: 'wrap',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <h2
              style={{ margin: 0, fontSize: '16px', fontWeight: 600, color: 'var(--color-text)' }}
            >
              Connected Accounts
            </h2>
            {addedMessage !== null && (
              <span
                role="status"
                aria-live="polite"
                style={{ fontSize: '13px', color: 'var(--color-success)', fontWeight: 500 }}
              >
                {addedMessage}
              </span>
            )}
          </div>

          <Button
            variant="primary"
            size="sm"
            onClick={() => setShowAddModal(true)}
            aria-label="Add connected account"
          >
            <Plus size={14} aria-hidden="true" />
            Add account
          </Button>
        </div>

        {/* Account list */}
        {isLoading ? (
          <div
            style={{ display: 'flex', justifyContent: 'center', padding: '32px' }}
            aria-live="polite"
            aria-label="Loading accounts"
          >
            <Spinner size="md" aria-label="Loading accounts" />
          </div>
        ) : accounts === undefined || accounts.length === 0 ? (
          <EmptyState
            variant="noResults"
            heading="No accounts connected"
            description="Add one to enable email, calendar, and other integrations."
            action={
              <Button variant="outline" size="sm" onClick={() => setShowAddModal(true)}>
                <Plus size={13} aria-hidden="true" />
                Add account
              </Button>
            }
          />
        ) : (
          <motion.div
            style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}
            layout
          >
            <AnimatePresence initial={false}>
              {accounts.map((account) => (
                <motion.div
                  key={account.id}
                  layout
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.97 }}
                  transition={{ duration: 0.2, ease: 'easeOut' }}
                >
                  <AccountCard account={account} onRemoved={handleRemoved} />
                </motion.div>
              ))}
            </AnimatePresence>
          </motion.div>
        )}
      </div>

      {/* Add account modal (portal-like via fixed position) */}
      <AnimatePresence>
        {showAddModal && (
          <motion.div
            key="add-modal"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
          >
            <AddAccountModal
              onClose={() => setShowAddModal(false)}
              onAdded={handleAdded}
            />
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

export default PoolManager;
