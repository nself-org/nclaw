'use client';

import React, { useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { MessageSquare } from 'lucide-react';
import { motion } from 'framer-motion';
import { GreetingBanner } from '@/components/chat/GreetingBanner';
import { InputBar } from '@/components/chat/InputBar';
import { useSessions } from '@/hooks/use-sessions';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import { AsyncScreen } from '@/components/ui/AsyncScreen';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { Skeleton } from '@/components/ui/Skeleton';

const MAX_RECENT = 5;

/** Returns a human-friendly relative time string, e.g. "2 hours ago". */
function relativeTime(isoString: string | null): string {
  if (!isoString) return '';
  try {
    const diff = Date.now() - new Date(isoString).getTime();
    if (diff < 60_000) return 'just now';
    if (diff < 3_600_000) {
      const m = Math.floor(diff / 60_000);
      return `${m} ${m === 1 ? 'minute' : 'minutes'} ago`;
    }
    if (diff < 86_400_000) {
      const h = Math.floor(diff / 3_600_000);
      return `${h} ${h === 1 ? 'hour' : 'hours'} ago`;
    }
    const d = Math.floor(diff / 86_400_000);
    if (d < 30) return `${d} ${d === 1 ? 'day' : 'days'} ago`;
    const mo = Math.floor(d / 30);
    if (mo < 12) return `${mo} ${mo === 1 ? 'month' : 'months'} ago`;
    const yr = Math.floor(mo / 12);
    return `${yr} ${yr === 1 ? 'year' : 'years'} ago`;
  } catch {
    return '';
  }
}

function ChatHomeSkeleton(): React.ReactElement {
  return (
    <div
      aria-label="Loading conversations"
      role="status"
      style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginTop: '32px' }}
    >
      <Skeleton variant="text" width="30%" height={14} />
      <Skeleton variant="rect" height={64} />
      <Skeleton variant="rect" height={64} />
      <Skeleton variant="rect" height={64} />
    </div>
  );
}

function ChatHomeEmpty(): React.ReactElement {
  return (
    <div
      role="status"
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '3rem 2rem',
        gap: '0.75rem',
        textAlign: 'center',
        color: 'var(--color-text-muted)',
      }}
    >
      <MessageSquare size={40} aria-hidden="true" />
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>No conversations yet</p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>
        Start your first conversation below — ɳClaw remembers everything.
      </p>
    </div>
  );
}

export default function ChatHomePage(): React.ReactElement {
  const router = useRouter();
  const { conversations, isLoading, error } = useSessions();
  const { isOnline } = useNetworkStatus();

  const recent = conversations.slice(0, MAX_RECENT);

  const handleConversationCreated = useCallback(
    (id: string) => {
      router.push(`/chat/${id}`);
    },
    [router],
  );

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
        overflow: 'hidden',
      }}
    >
      <OfflineBanner isOnline={isOnline} />

      {/* Scrollable main area */}
      <div
        style={{
          flex: 1,
          overflowY: 'auto',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          padding: '0 24px 24px',
        }}
      >
        <div style={{ width: '100%', maxWidth: '680px' }}>
          {/* Greeting banner */}
          <GreetingBanner />

          <AsyncScreen
            loading={isLoading}
            empty={conversations.length === 0}
            error={error ?? undefined}
            offline={!isOnline}
            skeleton={<ChatHomeSkeleton />}
            emptyContent={<ChatHomeEmpty />}
          >
            {/* Recent conversations */}
            {recent.length > 0 && (
              <section aria-labelledby="recent-heading" style={{ marginTop: '32px' }}>
                <h2
                  id="recent-heading"
                  style={{
                    margin: '0 0 12px',
                    fontSize: '13px',
                    fontWeight: 600,
                    letterSpacing: '0.06em',
                    textTransform: 'uppercase',
                    color: 'var(--color-text-muted)',
                  }}
                >
                  Recent
                </h2>

                <ul
                  role="list"
                  style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: '8px' }}
                >
                  {recent.map((conv, i) => (
                    <motion.li
                      key={conv.id}
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ duration: 0.2, delay: i * 0.04 }}
                    >
                      <button
                        type="button"
                        aria-label={`Open conversation: ${conv.title || 'Untitled'}`}
                        onClick={() => router.push(`/chat/${conv.id}`)}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: '12px',
                          width: '100%',
                          padding: '12px 16px',
                          borderRadius: '12px',
                          border: '1px solid var(--color-border)',
                          background: 'var(--color-bg-card)',
                          cursor: 'pointer',
                          textAlign: 'left',
                          transition: 'background 120ms ease, border-color 120ms ease',
                        }}
                        onMouseEnter={(e) => {
                          (e.currentTarget as HTMLButtonElement).style.background =
                            'rgba(255,255,255,0.08)';
                          (e.currentTarget as HTMLButtonElement).style.borderColor =
                            'rgba(255,255,255,0.18)';
                        }}
                        onMouseLeave={(e) => {
                          (e.currentTarget as HTMLButtonElement).style.background =
                            'var(--color-bg-card)';
                          (e.currentTarget as HTMLButtonElement).style.borderColor =
                            'var(--color-border)';
                        }}
                      >
                        {/* Icon */}
                        <span
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            width: '36px',
                            height: '36px',
                            borderRadius: '8px',
                            background: 'rgba(99,102,241,0.12)',
                            flexShrink: 0,
                            color: '#A5B4FC',
                          }}
                          aria-hidden="true"
                        >
                          <MessageSquare size={16} />
                        </span>

                        {/* Text */}
                        <span style={{ flex: 1, minWidth: 0 }}>
                          <span
                            style={{
                              display: 'block',
                              fontSize: '14px',
                              fontWeight: 500,
                              color: 'var(--color-text)',
                              overflow: 'hidden',
                              textOverflow: 'ellipsis',
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {conv.title || 'Untitled'}
                          </span>
                          <span
                            style={{
                              display: 'flex',
                              gap: '8px',
                              marginTop: '2px',
                              fontSize: '12px',
                              color: 'var(--color-text-muted)',
                            }}
                          >
                            <span>{relativeTime(conv.lastMessageAt ?? conv.updatedAt)}</span>
                            {conv.messageCount > 0 && (
                              <>
                                <span aria-hidden="true">·</span>
                                <span>
                                  {conv.messageCount}{' '}
                                  {conv.messageCount === 1 ? 'message' : 'messages'}
                                </span>
                              </>
                            )}
                          </span>
                        </span>
                      </button>
                    </motion.li>
                  ))}
                </ul>
              </section>
            )}
          </AsyncScreen>
        </div>
      </div>

      {/* Sticky input bar at bottom */}
      <div
        style={{
          flexShrink: 0,
          padding: '12px 24px 20px',
          borderTop: '1px solid var(--color-border)',
          background: 'var(--color-bg)',
        }}
      >
        <div style={{ maxWidth: '680px', margin: '0 auto' }}>
          <InputBar onConversationCreated={handleConversationCreated} />
        </div>
      </div>
    </div>
  );
}
