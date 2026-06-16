'use client';

/**
 * /knowledge — Knowledge base page with PDF, audio, and video ingest.
 *
 * Purpose: Display the user's knowledge items and provide Import buttons
 *          for PDF, audio, and video files. Each file type follows:
 *          file-picker → client-side size validation → XHR upload with
 *          progress bar (ProgressIngest) → knowledge item appears in list.
 *
 * Inputs:  No URL params.
 * Outputs: Knowledge item list + ingest modals per file type.
 *
 * Constraints:
 *  - PDF max 50 MB; audio max 200 MB; video max 200 MB (enforced client-side).
 *  - File size error shown before upload begins (no server round-trip).
 *  - Offline: upload buttons disabled; stale list shown if cached.
 *  - 7 UI states: initial, loading, empty, success, error, partial, offline.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: voice-call/pdf/audio/video ingest
 */

import React, { useCallback, useRef, useState } from 'react';
import { FileAudio, FilePlus, FileVideo, X } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import api from '@/lib/api';
import { getClawErrorMessage } from '@/lib/result';
import { Button } from '@/components/ui/Button';
import { Spinner } from '@/components/ui/Spinner';
import { ProgressIngest } from '@/components/knowledge/ProgressIngest';
import { isOffline } from '@/lib/offline-cache';
import type { IngestStep, KnowledgeItem } from '@/types';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_PDF_BYTES = 50 * 1024 * 1024;
const MAX_AUDIO_BYTES = 200 * 1024 * 1024;
const MAX_VIDEO_BYTES = 200 * 1024 * 1024;

const SIZE_LIMITS: Record<'pdf' | 'audio' | 'video', number> = {
  pdf: MAX_PDF_BYTES,
  audio: MAX_AUDIO_BYTES,
  video: MAX_VIDEO_BYTES,
};

const ACCEPT_TYPES: Record<'pdf' | 'audio' | 'video', string> = {
  pdf: '.pdf',
  audio: '.mp3,.wav,.ogg,.m4a',
  video: '.mp4,.mov,.webm,.avi',
};

const TYPE_LABELS: Record<'pdf' | 'audio' | 'video', string> = {
  pdf: 'PDF',
  audio: 'Audio',
  video: 'Video',
};

// ---------------------------------------------------------------------------
// Ingest modal
// ---------------------------------------------------------------------------

interface IngestModalProps {
  type: 'pdf' | 'audio' | 'video';
  onClose: () => void;
  onSuccess: (item: KnowledgeItem) => void;
}

function IngestModal({ type, onClose, onSuccess }: IngestModalProps): React.ReactElement {
  const fileRef = useRef<HTMLInputElement>(null);
  const [step, setStep] = useState<IngestStep>('uploading');
  const [percent, setPercent] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [inProgress, setInProgress] = useState(false);

  const handleFile = useCallback(
    async (file: File) => {
      // Client-side size validation — before upload
      const limit = SIZE_LIMITS[type];
      if (file.size > limit) {
        const limitMb = Math.round(limit / 1024 / 1024);
        setError(`File too large. Maximum size for ${TYPE_LABELS[type]} is ${limitMb} MB.`);
        return;
      }

      setError(null);
      setInProgress(true);
      setStep('uploading');
      setPercent(0);

      const result = await api.ingestFile(type, file, (pct) => {
        setPercent(pct);
        if (pct === 100) setStep('processing');
      });

      if (!result.ok) {
        setError(getClawErrorMessage(result.error));
        setInProgress(false);
        return;
      }

      setStep('indexing');
      await new Promise((r) => setTimeout(r, 600));
      setStep('done');
      await new Promise((r) => setTimeout(r, 400));

      onSuccess(result.value);
    },
    [type, onSuccess]
  );

  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) void handleFile(file);
    },
    [handleFile]
  );

  const handleDrop = useCallback(
    (e: React.DragEvent<HTMLDivElement>) => {
      e.preventDefault();
      const file = e.dataTransfer.files?.[0];
      if (file) void handleFile(file);
    },
    [handleFile]
  );

  const limitMb = Math.round(SIZE_LIMITS[type] / 1024 / 1024);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Import ${TYPE_LABELS[type]}`}
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1000,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'rgba(0,0,0,0.6)',
        backdropFilter: 'blur(4px)',
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget && !inProgress) onClose();
      }}
    >
      <div
        style={{
          width: '100%',
          maxWidth: 480,
          margin: '0 16px',
          borderRadius: 16,
          background: 'var(--color-surface, #18181b)',
          border: '1px solid rgba(255,255,255,0.1)',
          padding: 24,
          display: 'flex',
          flexDirection: 'column',
          gap: 20,
        }}
      >
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <h2 style={{ fontSize: 16, fontWeight: 700, color: 'var(--color-text)' }}>
            Import {TYPE_LABELS[type]}
          </h2>
          {!inProgress && (
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              style={{
                background: 'none',
                border: 'none',
                cursor: 'pointer',
                color: 'var(--color-text-muted)',
                padding: 4,
                borderRadius: 4,
              }}
            >
              <X size={18} />
            </button>
          )}
        </div>

        {/* Drop zone (shown before ingest starts) */}
        {!inProgress && !error && (
          <div
            onDrop={handleDrop}
            onDragOver={(e) => e.preventDefault()}
            onClick={() => fileRef.current?.click()}
            role="button"
            tabIndex={0}
            aria-label={`Click or drop a ${TYPE_LABELS[type]} file`}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') fileRef.current?.click();
            }}
            style={{
              border: '2px dashed rgba(255,255,255,0.15)',
              borderRadius: 12,
              padding: '40px 20px',
              textAlign: 'center',
              cursor: 'pointer',
              transition: 'border-color 0.2s',
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLElement).style.borderColor = 'var(--color-primary, #6366f1)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.borderColor = 'rgba(255,255,255,0.15)';
            }}
          >
            <p style={{ color: 'var(--color-text)', fontSize: 14, marginBottom: 4 }}>
              Drop a {TYPE_LABELS[type]} file here or click to browse
            </p>
            <p style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>
              Max {limitMb} MB &middot; {ACCEPT_TYPES[type]}
            </p>
          </div>
        )}

        {/* Progress (shown during ingest) */}
        {inProgress && <ProgressIngest step={step} percent={percent} error={null} />}

        {/* Error state */}
        {error && !inProgress && (
          <>
            <ProgressIngest step="uploading" error={error} />
            <Button
              variant="ghost"
              onClick={() => {
                setError(null);
                setPercent(0);
              }}
            >
              Try Again
            </Button>
          </>
        )}

        {/* Hidden file input */}
        <input
          ref={fileRef}
          type="file"
          accept={ACCEPT_TYPES[type]}
          style={{ display: 'none' }}
          onChange={handleInputChange}
          aria-hidden="true"
        />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Knowledge item card
// ---------------------------------------------------------------------------

function KnowledgeCard({ item }: { item: KnowledgeItem }): React.ReactElement {
  const icons: Record<string, React.ReactElement> = {
    pdf: <FilePlus size={18} style={{ color: 'var(--color-primary, #6366f1)' }} />,
    audio: <FileAudio size={18} style={{ color: '#22c55e' }} />,
    video: <FileVideo size={18} style={{ color: '#f59e0b' }} />,
    text: <FilePlus size={18} style={{ color: 'var(--color-text-muted)' }} />,
  };

  const sizeMb = (item.sizeBytes / 1024 / 1024).toFixed(1);

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: 12,
        padding: '12px 16px',
        borderRadius: 10,
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.07)',
      }}
    >
      <div style={{ flexShrink: 0, paddingTop: 2 }}>
        {icons[item.type] ?? icons.text}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <p
          style={{
            fontSize: 14,
            fontWeight: 600,
            color: 'var(--color-text)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {item.title || item.sourceFilename}
        </p>
        {item.summary && (
          <p
            style={{
              fontSize: 12,
              color: 'var(--color-text-muted)',
              marginTop: 2,
              display: '-webkit-box',
              WebkitLineClamp: 2,
              WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
            }}
          >
            {item.summary}
          </p>
        )}
        <p style={{ fontSize: 11, color: 'var(--color-text-muted)', marginTop: 4 }}>
          {item.type.toUpperCase()} &middot; {sizeMb} MB &middot;{' '}
          {new Date(item.createdAt).toLocaleDateString()}
        </p>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function KnowledgePage(): React.ReactElement {
  const queryClient = useQueryClient();
  const [activeModal, setActiveModal] = useState<'pdf' | 'audio' | 'video' | null>(null);
  const offline = isOffline();

  const { data, isLoading, error } = useQuery({
    queryKey: ['knowledge'],
    queryFn: async () => {
      const result = await api.listKnowledge(1, 50);
      if (!result.ok) throw new Error(getClawErrorMessage(result.error));
      return result.value.data;
    },
    staleTime: 60_000,
  });

  const handleSuccess = useCallback(
    (item: KnowledgeItem) => {
      setActiveModal(null);
      // Optimistically prepend new item to cache
      queryClient.setQueryData<KnowledgeItem[]>(['knowledge'], (prev = []) => [item, ...prev]);
    },
    [queryClient]
  );

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
        padding: '32px 24px',
        maxWidth: 720,
        margin: '0 auto',
        gap: 24,
      }}
    >
      {/* Header + import buttons */}
      <div
        style={{
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 12,
        }}
      >
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 700, color: 'var(--color-text)', marginBottom: 6 }}>
            Knowledge
          </h1>
          <p style={{ fontSize: 14, color: 'var(--color-text-muted)' }}>
            Import documents, audio, and video to grow &#x0149;Claw&apos;s knowledge base.
          </p>
        </div>

        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <Button
            variant="ghost"
            onClick={() => setActiveModal('pdf')}
            disabled={offline}
            title={offline ? 'Offline — unavailable' : 'Import PDF'}
          >
            <FilePlus size={15} /> Import PDF
          </Button>
          <Button
            variant="ghost"
            onClick={() => setActiveModal('audio')}
            disabled={offline}
            title={offline ? 'Offline — unavailable' : 'Import Audio'}
          >
            <FileAudio size={15} /> Import Audio
          </Button>
          <Button
            variant="ghost"
            onClick={() => setActiveModal('video')}
            disabled={offline}
            title={offline ? 'Offline — unavailable' : 'Import Video'}
          >
            <FileVideo size={15} /> Import Video
          </Button>
        </div>
      </div>

      {/* Offline banner */}
      {offline && (
        <div
          role="status"
          style={{
            padding: '10px 14px',
            borderRadius: 8,
            background: 'rgba(234,179,8,0.1)',
            color: 'var(--color-warning, #eab308)',
            fontSize: 13,
          }}
        >
          You are offline. Imports are unavailable.
        </div>
      )}

      {/* Loading */}
      {isLoading && (
        <div
          role="status"
          aria-label="Loading knowledge items"
          style={{ display: 'flex', justifyContent: 'center', paddingTop: 48 }}
        >
          <Spinner size="lg" />
        </div>
      )}

      {/* Error */}
      {error && !isLoading && (
        <div
          role="alert"
          style={{
            padding: '12px 16px',
            borderRadius: 8,
            background: 'rgba(239,68,68,0.1)',
            color: 'var(--color-error, #ef4444)',
            fontSize: 14,
          }}
        >
          {error instanceof Error ? error.message : 'Failed to load knowledge items.'}
        </div>
      )}

      {/* Empty */}
      {!isLoading && !error && data?.length === 0 && (
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 12,
            paddingTop: 80,
            color: 'var(--color-text-muted)',
          }}
        >
          <FilePlus size={40} style={{ opacity: 0.3 }} />
          <p style={{ fontSize: 15, fontWeight: 500 }}>No knowledge items yet</p>
          <p style={{ fontSize: 13, textAlign: 'center', maxWidth: 320 }}>
            Import a PDF, audio recording, or video to start building the knowledge base.
          </p>
        </div>
      )}

      {/* List */}
      {!isLoading && data && data.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, overflowY: 'auto' }}>
          {data.map((item) => (
            <KnowledgeCard key={item.id} item={item} />
          ))}
        </div>
      )}

      {/* Modals */}
      {activeModal && (
        <IngestModal
          type={activeModal}
          onClose={() => setActiveModal(null)}
          onSuccess={handleSuccess}
        />
      )}
    </div>
  );
}
