'use client';

/**
 * ProgressIngest.tsx
 *
 * Purpose: Multi-step progress indicator shared by the PDF, audio, and video
 *          ingest flows.  Steps are: uploading → processing → indexing → done.
 *
 * Inputs:
 *   step     — current active step
 *   percent  — 0-100 upload progress (shown only during 'uploading' step)
 *   error    — error message to display; clears the step indicators
 *
 * Outputs: Renders a stepped progress UI; no callbacks.
 *
 * Constraints: Pure display component, no API calls.
 */

import React from 'react';
import type { IngestStep } from '@/types';

const STEPS: { id: IngestStep; label: string }[] = [
  { id: 'uploading', label: 'Uploading' },
  { id: 'processing', label: 'Processing' },
  { id: 'indexing', label: 'Indexing' },
  { id: 'done', label: 'Done' },
];

const STEP_INDEX: Record<IngestStep, number> = {
  uploading: 0,
  processing: 1,
  indexing: 2,
  done: 3,
};

interface ProgressIngestProps {
  step: IngestStep;
  percent?: number;
  error?: string | null;
}

export function ProgressIngest({
  step,
  percent,
  error,
}: ProgressIngestProps): React.ReactElement {
  const activeIdx = STEP_INDEX[step];

  if (error) {
    return (
      <div
        role="alert"
        style={{
          padding: '12px 16px',
          borderRadius: 8,
          background: 'rgba(239,68,68,0.12)',
          color: 'var(--color-error, #ef4444)',
          fontSize: 14,
        }}
      >
        {error}
      </div>
    );
  }

  return (
    <div aria-live="polite" aria-label="Ingest progress" style={{ width: '100%' }}>
      {/* Step dots */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 0,
          marginBottom: 8,
        }}
      >
        {STEPS.map((s, idx) => {
          const done = idx < activeIdx;
          const active = idx === activeIdx;
          return (
            <React.Fragment key={s.id}>
              {/* Connector line */}
              {idx > 0 && (
                <div
                  style={{
                    flex: 1,
                    height: 2,
                    background: done || active ? 'var(--color-primary, #6366f1)' : 'rgba(255,255,255,0.1)',
                    transition: 'background 0.3s',
                  }}
                />
              )}
              {/* Step dot */}
              <div
                title={s.label}
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: '50%',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  background: done
                    ? 'var(--color-primary, #6366f1)'
                    : active
                    ? 'var(--color-primary, #6366f1)'
                    : 'rgba(255,255,255,0.1)',
                  border: active ? '2px solid var(--color-primary, #6366f1)' : '2px solid transparent',
                  transition: 'background 0.3s, border-color 0.3s',
                  flexShrink: 0,
                }}
              >
                {active && step !== 'done' ? (
                  <svg
                    width="10"
                    height="10"
                    viewBox="0 0 10 10"
                    fill="none"
                    role="status"
                    aria-label="Loading"
                    style={{ animation: 'nclaw-spin 700ms linear infinite', transformOrigin: 'center' }}
                  >
                    <circle cx="5" cy="5" r="3.5" stroke="#fff" strokeWidth="1.5" strokeLinecap="round" strokeDasharray="22" strokeDashoffset="16.5" opacity="0.9" />
                  </svg>
                ) : done || step === 'done' ? (
                  <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                    <path d="M1.5 5l2.5 2.5 4.5-5" stroke="#fff" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                ) : null}
              </div>
            </React.Fragment>
          );
        })}
      </div>

      {/* Step labels */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          fontSize: 11,
          color: 'var(--color-text-muted)',
          marginBottom: 8,
        }}
      >
        {STEPS.map((s, idx) => (
          <span
            key={s.id}
            style={{
              color:
                idx <= activeIdx ? 'var(--color-text, #fff)' : 'var(--color-text-muted)',
              fontWeight: idx === activeIdx ? 600 : 400,
              transition: 'color 0.3s',
            }}
          >
            {s.label}
          </span>
        ))}
      </div>

      {/* Upload progress bar */}
      {step === 'uploading' && percent !== undefined && (
        <div
          style={{
            height: 4,
            borderRadius: 2,
            background: 'rgba(255,255,255,0.1)',
            overflow: 'hidden',
          }}
        >
          <div
            role="progressbar"
            aria-valuenow={percent}
            aria-valuemin={0}
            aria-valuemax={100}
            style={{
              height: '100%',
              width: `${percent}%`,
              background: 'var(--color-primary, #6366f1)',
              transition: 'width 0.2s linear',
            }}
          />
        </div>
      )}
    </div>
  );
}
