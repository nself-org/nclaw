'use client';

import React, { useState, useCallback } from 'react';
import { useMutation } from '@tanstack/react-query';
import { Camera } from 'lucide-react';
import api from '@/lib/api';
import { useAppStore } from '@/store/app-store';
import type { User } from '@/types';

const AVATAR_SIZE = 80;
const BIO_MAX_LENGTH = 280;

type SavePayload = Partial<Pick<User, 'displayName' | 'bio' | 'avatarUrl'>>;

function getInitials(displayName: string | null | undefined, email: string | null | undefined): string {
  if (displayName?.trim()) {
    const parts = displayName.trim().split(/\s+/);
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
    }
    return (parts[0][0] ?? '?').toUpperCase();
  }
  if (email?.trim()) {
    return (email[0] ?? '?').toUpperCase();
  }
  return '?';
}

interface SaveStatus {
  type: 'idle' | 'saving' | 'saved' | 'error';
  message: string | null;
}

export function BioAvatar(): React.ReactElement {
  const user = useAppStore((s) => s.user);
  const settings = useAppStore((s) => s.settings);
  const setUser = useAppStore((s) => s.setUser);
  const setSettings = useAppStore((s) => s.setSettings);

  const resolvedDisplayName = settings?.displayName ?? user?.displayName ?? '';
  const resolvedBio = settings?.bio ?? user?.bio ?? '';
  const resolvedAvatarUrl = settings?.avatarUrl ?? user?.avatarUrl ?? null;

  const [displayName, setDisplayName] = useState<string>(resolvedDisplayName);
  const [bio, setBio] = useState<string>(resolvedBio);
  const [saveStatus, setSaveStatus] = useState<SaveStatus>({ type: 'idle', message: null });
  const [isAvatarHovered, setIsAvatarHovered] = useState(false);

  const mutation = useMutation<User, Error, SavePayload>({
    mutationFn: (payload) => api.updateMe(payload),
    onSuccess: (updated) => {
      setUser(updated);
      if (settings) {
        setSettings({
          ...settings,
          displayName: updated.displayName,
          bio: updated.bio,
          avatarUrl: updated.avatarUrl,
        });
      }
      setSaveStatus({ type: 'saved', message: 'Saved' });
      const timer = setTimeout(
        () => setSaveStatus({ type: 'idle', message: null }),
        2500
      );
      return () => clearTimeout(timer);
    },
    onError: (err) => {
      setSaveStatus({ type: 'error', message: err.message ?? 'Failed to save' });
    },
  });

  const handleBlur = useCallback(
    (field: 'displayName' | 'bio') => {
      const trimmedName = displayName.trim();
      const trimmedBio = bio.trim();

      const currentName = settings?.displayName ?? user?.displayName ?? '';
      const currentBio = settings?.bio ?? user?.bio ?? '';

      const nameChanged = field === 'displayName' && trimmedName !== currentName;
      const bioChanged = field === 'bio' && trimmedBio !== currentBio;

      if (!nameChanged && !bioChanged) return;

      setSaveStatus({ type: 'saving', message: null });
      mutation.mutate({
        displayName: field === 'displayName' ? trimmedName || null : (currentName || null),
        bio: field === 'bio' ? trimmedBio || null : (currentBio || null),
      });
    },
    [displayName, bio, settings, user, mutation]
  );

  const initials = getInitials(displayName || resolvedDisplayName, user?.email);

  return (
    <div className="flex flex-col gap-6">
      {/* Avatar */}
      <div className="flex items-center gap-5">
        <div
          className="relative flex-shrink-0 rounded-full overflow-hidden cursor-default select-none"
          style={{
            width: AVATAR_SIZE,
            height: AVATAR_SIZE,
            background: resolvedAvatarUrl
              ? undefined
              : 'linear-gradient(135deg, #0EA5E9 0%, #2563EB 100%)',
          }}
          onMouseEnter={() => setIsAvatarHovered(true)}
          onMouseLeave={() => setIsAvatarHovered(false)}
          aria-label="Profile avatar — upload coming soon"
          title="Upload coming soon"
        >
          {resolvedAvatarUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={resolvedAvatarUrl}
              alt="Profile avatar"
              width={AVATAR_SIZE}
              height={AVATAR_SIZE}
              className="w-full h-full object-cover"
            />
          ) : (
            <span
              className="flex items-center justify-center w-full h-full text-2xl font-semibold"
              style={{ color: '#ffffff' }}
              aria-hidden="true"
            >
              {initials}
            </span>
          )}

          {/* Camera hover overlay */}
          {isAvatarHovered && (
            <div
              className="absolute inset-0 flex items-center justify-center"
              style={{ background: 'rgba(0,0,0,0.55)' }}
            >
              <Camera
                size={22}
                style={{ color: '#ffffff' }}
                aria-hidden="true"
              />
            </div>
          )}
        </div>

        <div className="flex flex-col gap-1">
          <p
            className="text-sm font-medium"
            style={{ color: 'var(--color-text)' }}
          >
            {resolvedDisplayName || user?.email || 'Your profile'}
          </p>
          <p className="text-xs" style={{ color: 'var(--color-text-muted)' }}>
            {user?.email ?? ''}
          </p>
          <p className="text-xs" style={{ color: 'var(--color-text-muted)' }}>
            Avatar upload coming soon
          </p>
        </div>
      </div>

      {/* Display name */}
      <div className="flex flex-col gap-1.5">
        <label
          htmlFor="bio-avatar-display-name"
          className="text-sm font-medium"
          style={{ color: 'var(--color-text)' }}
        >
          Display name
        </label>
        <input
          id="bio-avatar-display-name"
          type="text"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          onBlur={() => handleBlur('displayName')}
          placeholder="Your name"
          maxLength={80}
          className="rounded-lg px-3 py-2 text-sm transition-colors"
          style={{
            background: 'var(--color-bg-input)',
            border: '1px solid var(--color-border)',
            color: 'var(--color-text)',
            outline: 'none',
          }}
          onFocus={(e) => {
            e.currentTarget.style.borderColor = 'var(--color-border-focus)';
          }}
          onBlurCapture={(e) => {
            e.currentTarget.style.borderColor = 'var(--color-border)';
          }}
          aria-label="Display name"
        />
      </div>

      {/* Bio */}
      <div className="flex flex-col gap-1.5">
        <div className="flex items-center justify-between">
          <label
            htmlFor="bio-avatar-bio"
            className="text-sm font-medium"
            style={{ color: 'var(--color-text)' }}
          >
            Bio
          </label>
          <span
            className="text-xs tabular-nums"
            style={{
              color: bio.length > BIO_MAX_LENGTH * 0.9
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
          id="bio-avatar-bio"
          value={bio}
          onChange={(e) => setBio(e.target.value.slice(0, BIO_MAX_LENGTH))}
          onBlur={() => handleBlur('bio')}
          placeholder="Tell ɳClaw about yourself"
          rows={3}
          maxLength={BIO_MAX_LENGTH}
          className="rounded-lg px-3 py-2 text-sm resize-none transition-colors"
          style={{
            background: 'var(--color-bg-input)',
            border: '1px solid var(--color-border)',
            color: 'var(--color-text)',
            outline: 'none',
          }}
          onFocus={(e) => {
            e.currentTarget.style.borderColor = 'var(--color-border-focus)';
          }}
          onBlurCapture={(e) => {
            e.currentTarget.style.borderColor = 'var(--color-border)';
          }}
          aria-label="Bio"
          aria-describedby="bio-avatar-bio-count"
        />
        <span id="bio-avatar-bio-count" className="sr-only">
          {bio.length} of {BIO_MAX_LENGTH} characters used
        </span>
      </div>

      {/* Save status */}
      {saveStatus.type !== 'idle' && (
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
          {saveStatus.type === 'saving' ? 'Saving…' : saveStatus.message}
        </p>
      )}
    </div>
  );
}

export default BioAvatar;
