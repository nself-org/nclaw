'use client';

import React, { useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAppStore } from '@/store/app-store';
import api from '@/lib/api';
import { Button } from '@/components/ui/Button';
import { GlassCard } from '@/components/ui/GlassCard';
import { Input } from '@/components/ui/Input';

export default function LoginPage(): React.ReactElement {
  const router = useRouter();
  const { setTokens, setUser, onboardingComplete } = useAppStore();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [setupTooltipVisible, setSetupTooltipVisible] = useState(false);

  const createAccountBtnRef = useRef<HTMLButtonElement>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!email.trim() || !password.trim()) {
      setError('Email and password are required.');
      return;
    }

    setLoading(true);
    const tokensResult = await api.signIn(email.trim(), password);
    if (!tokensResult.ok) {
      setError(tokensResult.error.message ?? 'Sign in failed. Please check your credentials.');
      setLoading(false);
      return;
    }
    const tokens = tokensResult.value;
    setTokens(tokens);
    api.setToken(tokens.accessToken);

    const userResult = await api.getMe();
    if (!userResult.ok) {
      setError(userResult.error.message ?? 'Failed to load profile.');
      setLoading(false);
      return;
    }
    setUser(userResult.value);

    setLoading(false);
    router.replace(onboardingComplete ? '/' : '/onboarding');
  };

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
    >
      <GlassCard
        variant="modal"
        style={{
          width: '100%',
          maxWidth: 400,
          padding: '40px 36px',
        }}
      >
        {/* Logo + Title */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div
            style={{
              fontSize: '2.5rem',
              fontWeight: 900,
              color: 'var(--color-primary-text)',
              lineHeight: 1,
              marginBottom: 12,
              letterSpacing: '-0.02em',
              userSelect: 'none',
            }}
            aria-hidden="true"
          >
            ɳ
          </div>
          <h1
            style={{
              fontSize: 22,
              fontWeight: 700,
              color: 'var(--color-text)',
              margin: 0,
            }}
          >
            Sign in to ɳClaw
          </h1>
        </div>

        <form onSubmit={handleSubmit} noValidate>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginBottom: 24 }}>
            <Input
              type="email"
              label="Email"
              placeholder="you@example.com"
              autoComplete="email"
              value={email}
              onChange={(e) => { setEmail(e.target.value); setError(null); }}
              disabled={loading}
            />
            <Input
              type="password"
              label="Password"
              placeholder="••••••••"
              autoComplete="current-password"
              value={password}
              onChange={(e) => { setPassword(e.target.value); setError(null); }}
              disabled={loading}
            />
          </div>

          {error && (
            <div
              role="alert"
              style={{
                marginBottom: 16,
                padding: '10px 14px',
                borderRadius: 8,
                background: 'rgba(248,113,113,0.08)',
                border: '1px solid rgba(248,113,113,0.2)',
                fontSize: 13,
                color: 'var(--color-error)',
                lineHeight: 1.5,
              }}
            >
              {error}
            </div>
          )}

          <Button
            type="submit"
            size="lg"
            loading={loading}
            style={{ width: '100%', marginBottom: 16 }}
          >
            Sign in
          </Button>
        </form>

        {/* Create account */}
        <div style={{ textAlign: 'center', position: 'relative' }}>
          <button
            ref={createAccountBtnRef}
            type="button"
            onClick={() => setSetupTooltipVisible((v) => !v)}
            onBlur={() => setTimeout(() => setSetupTooltipVisible(false), 150)}
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
            Create account
          </button>

          {setupTooltipVisible && (
            <div
              role="tooltip"
              style={{
                position: 'absolute',
                bottom: 'calc(100% + 8px)',
                left: '50%',
                transform: 'translateX(-50%)',
                whiteSpace: 'nowrap',
                background: 'rgba(22,22,42,0.98)',
                border: '1px solid var(--color-border)',
                borderRadius: 8,
                padding: '8px 14px',
                fontSize: 13,
                color: 'var(--color-text-muted)',
                boxShadow: 'var(--shadow-modal)',
                pointerEvents: 'none',
              }}
            >
              Self-hosted setup required.{' '}
              <a
                href="https://docs.nself.org/getting-started/quick-start"
                target="_blank"
                rel="noopener noreferrer"
                style={{
                  color: 'var(--color-primary-text)',
                  textDecoration: 'underline',
                  textUnderlineOffset: 3,
                  pointerEvents: 'auto',
                }}
              >
                Get started →
              </a>
            </div>
          )}
        </div>
      </GlassCard>
    </div>
  );
}
