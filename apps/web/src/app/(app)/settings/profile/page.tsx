'use client';

import React, { useState, useCallback } from 'react';
import { useMutation } from '@tanstack/react-query';
import { BioAvatar } from '@/components/profile/BioAvatar';
import { useAppStore } from '@/store/app-store';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import api from '@/lib/api';
import type { SettingsData, User } from '@/types';

const BIO_MAX_LENGTH = 280;

type SavePayload = Partial<Pick<User, 'displayName' | 'bio'>>;

interface SaveStatus {
  type: 'idle' | 'saving' | 'saved' | 'error';
  message: string | null;
}

function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(new Date(iso));
}

export default function ProfileSettingsPage(): React.ReactElement {
  const { isOnline } = useNetworkStatus();
  const user = useAppStore((s) => s.user);
  const settings = useAppStore((s) => s.settings);
  const setUser = useAppStore((s) => s.setUser);
  const setSettings = useAppStore((s) => s.setSettings);

  const initialDisplayName = settings?.displayName ?? user?.displayName ?? '';
  const initialBio = settings?.bio ?? user?.bio ?? '';

  const [displayName, setDisplayName] = useState<string>(initialDisplayName);
  const [bio, setBio] = useState<string>(initialBio);
  const [saveStatus, setSaveStatus] = useState<SaveStatus>({ type: 'idle', message: null });

  const mutation = useMutation<User, Error, SavePayload>({
    mutationFn: async (payload) => {
      const r = await api.updateMe(payload);
      if (!r.ok) throw new Error(r.error.message);
      return r.value;
    },
    onSuccess: (updated) => {
      setUser(updated);
      if (settings) {
        const next: SettingsData = {
          ...settings,
          displayName: updated.displayName,
          bio: updated.bio,
          avatarUrl: updated.avatarUrl,
        };
        setSettings(next);
      }
      setSaveStatus({ type: 'saved', message: 'Changes saved' });
      const timer = setTimeout(
        () => setSaveStatus({ type: 'idle', message: null }),
        3000
      );
      return () => clearTimeout(timer);
    },
    onError: (err) => {
      setSaveStatus({ type: 'error', message: err.message ?? 'Failed to save changes' });
    },
  });

  const handleSave = useCallback(() => {
    setSaveStatus({ type: 'saving', message: null });
    mutation.mutate({
      displayName: displayName.trim() || null,
      bio: bio.trim() || null,
    });
  }, [displayName, bio, mutation]);

  return (
    <div className="mx-auto max-w-xl w-full px-4 py-10 flex flex-col gap-8">
      <OfflineBanner isOnline={isOnline} />
      <header>
        <h1
          className="text-2xl font-semibold"
          style={{ color: 'var(--color-text)' }}
        >
          Profile
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--color-text-muted)' }}>
          How ɳClaw knows you
        </p>
      </header>

      {/* Avatar + inline bio/name editor (auto-saves on blur) */}
      <section aria-label="Avatar and bio">
        <BioAvatar />
      </section>

      <hr style={{ borderColor: 'var(--color-border)' }} />

      {/* Full form with save button */}
      <section aria-label="Profile details" className="flex flex-col gap-5">
        {/* Display name */}
        <div className="flex flex-col gap-1.5">
          <label
            htmlFor="profile-display-name"
            className="text-sm font-medium"
            style={{ color: 'var(--color-text)' }}
          >
            Display name
          </label>
          <input
            id="profile-display-name"
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Your name"
            maxLength={80}
            className="rounded-lg px-3 py-2 text-sm"
            style={{
              background: 'var(--color-bg-input)',
              border: '1px solid var(--color-border)',
              color: 'var(--color-text)',
              outline: 'none',
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderColor = 'var(--color-border-focus)';
            }}
            onBlur={(e) => {
              e.currentTarget.style.borderColor = 'var(--color-border)';
            }}
            aria-label="Display name"
          />
        </div>

        {/* Bio */}
        <div className="flex flex-col gap-1.5">
          <div className="flex items-center justify-between">
            <label
              htmlFor="profile-bio"
              className="text-sm font-medium"
              style={{ color: 'var(--color-text)' }}
            >
              Bio
            </label>
            <span
              className="text-xs tabular-nums"
              style={{
                color:
                  bio.length > BIO_MAX_LENGTH * 0.9
                    ? 'var(--color-warning)'
                    : 'var(--color-text-muted)',
              }}
              aria-live="polite"
              aria-atomic="true"
            >
              {bio.length}/{BIO_MAX_LENGTH}
            </span>
          </div>
          <textarea
            id="profile-bio"
            value={bio}
            onChange={(e) => setBio(e.target.value.slice(0, BIO_MAX_LENGTH))}
            placeholder="Tell ɳClaw about yourself"
            rows={4}
            maxLength={BIO_MAX_LENGTH}
            className="rounded-lg px-3 py-2 text-sm resize-none"
            style={{
              background: 'var(--color-bg-input)',
              border: '1px solid var(--color-border)',
              color: 'var(--color-text)',
              outline: 'none',
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderColor = 'var(--color-border-focus)';
            }}
            onBlur={(e) => {
              e.currentTarget.style.borderColor = 'var(--color-border)';
            }}
            aria-label="Bio"
            aria-describedby="profile-bio-count"
          />
          <span id="profile-bio-count" className="sr-only">
            {bio.length} of {BIO_MAX_LENGTH} characters used
          </span>
        </div>

        {/* Email — read-only */}
        <div className="flex flex-col gap-1.5">
          <label
            htmlFor="profile-email"
            className="text-sm font-medium"
            style={{ color: 'var(--color-text)' }}
          >
            Email
          </label>
          <input
            id="profile-email"
            type="email"
            value={user?.email ?? ''}
            readOnly
            disabled
            className="rounded-lg px-3 py-2 text-sm cursor-default"
            style={{
              background: 'var(--color-bg-card)',
              border: '1px solid var(--color-border)',
              color: 'var(--color-text-muted)',
              outline: 'none',
            }}
            aria-label="Email address (read-only)"
          />
          <p className="text-xs" style={{ color: 'var(--color-text-muted)' }}>
            Email cannot be changed here.
          </p>
        </div>

        {/* Account created — read-only */}
        <div className="flex flex-col gap-1">
          <p className="text-sm font-medium" style={{ color: 'var(--color-text)' }}>
            Account created
          </p>
          <p className="text-sm" style={{ color: 'var(--color-text-muted)' }}>
            {formatDate(user?.createdAt)}
          </p>
        </div>

        {/* Save */}
        <div className="flex items-center gap-4 pt-2">
          <button
            type="button"
            onClick={handleSave}
            disabled={mutation.isPending}
            className="rounded-lg px-5 py-2 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
            style={{
              background: 'var(--color-primary)',
              color: '#ffffff',
              opacity: mutation.isPending ? 0.6 : 1,
              cursor: mutation.isPending ? 'not-allowed' : 'pointer',
            }}
            aria-busy={mutation.isPending}
            aria-label="Save profile changes"
          >
            {mutation.isPending ? 'Saving…' : 'Save changes'}
          </button>

          {saveStatus.type !== 'idle' && !mutation.isPending && (
            <p
              className="text-sm"
              role="status"
              aria-live="polite"
              style={{
                color:
                  saveStatus.type === 'saved'
                    ? 'var(--color-success)'
                    : saveStatus.type === 'error'
                    ? 'var(--color-error)'
                    : 'var(--color-text-muted)',
              }}
            >
              {saveStatus.message}
            </p>
          )}
        </div>
      </section>
    </div>
  );
}
