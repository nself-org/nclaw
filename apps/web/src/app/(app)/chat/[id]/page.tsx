'use client';

import React, { useCallback, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useChatStore } from '@/store/chat-store';
import { useMessages } from '@/hooks/use-messages';
import { MessageList } from '@/components/chat/MessageList';
import { InputBar } from '@/components/chat/InputBar';
import { AsyncScreen } from '@/components/ui/AsyncScreen';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { Skeleton } from '@/components/ui/Skeleton';
import { useNetworkStatus } from '@/hooks/useNetworkStatus';

// ---------------------------------------------------------------------------
// Skeleton loading state — message bubble rows matching populated layout
// ---------------------------------------------------------------------------

function MessageSkeletons(): React.ReactElement {
  return (
    <div
      aria-label="Loading messages"
      role="status"
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: '16px',
        padding: '24px',
        flex: 1,
      }}
    >
      {/* User bubble — right-aligned */}
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <Skeleton variant="rect" width="55%" height={52} />
      </div>
      {/* Assistant bubble — left-aligned */}
      <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
        <Skeleton variant="rect" width="72%" height={88} />
      </div>
      {/* User bubble — right-aligned */}
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <Skeleton variant="rect" width="40%" height={52} />
      </div>
    </div>
  );
}

function ChatEmpty(): React.ReactElement {
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
      <p style={{ margin: 0, fontWeight: 600, color: 'var(--color-text)' }}>
        Start the conversation
      </p>
      <p style={{ margin: 0, fontSize: '0.875rem' }}>
        Send your first message below.
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Inner page — receives resolved conversationId string
// ---------------------------------------------------------------------------

interface ConversationPageInnerProps {
  conversationId: string;
}

function ConversationPageInner({
  conversationId,
}: ConversationPageInnerProps): React.ReactElement {
  const router = useRouter();
  const setCurrentConversationId = useChatStore((s) => s.setCurrentConversationId);
  const { isOnline } = useNetworkStatus();

  const { messages, isLoading, error } = useMessages(conversationId);

  // Register the active conversation in global store.
  useEffect(() => {
    setCurrentConversationId(conversationId);
    return () => {
      setCurrentConversationId(null);
    };
  }, [conversationId, setCurrentConversationId]);

  const handleRetry = useCallback(() => {
    router.refresh();
  }, [router]);

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

      <AsyncScreen
        loading={isLoading}
        empty={messages.length === 0}
        error={error ?? undefined}
        offline={!isOnline}
        onRetry={handleRetry}
        skeleton={<MessageSkeletons />}
        emptyContent={<ChatEmpty />}
      >
        {/* Message list — scrollable */}
        <div style={{ flex: 1, overflow: 'hidden' }}>
          <MessageList conversationId={conversationId} />
        </div>
      </AsyncScreen>

      {/* Input bar — always visible below messages */}
      <div
        style={{
          flexShrink: 0,
          padding: '12px 24px 20px',
          borderTop: '1px solid var(--color-border)',
          background: 'var(--color-bg)',
        }}
      >
        <div style={{ maxWidth: '680px', margin: '0 auto' }}>
          <InputBar conversationId={conversationId} />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page — Next.js 14 client page with dynamic params
// ---------------------------------------------------------------------------

interface ChatPageProps {
  params: { id: string };
}

export default function ChatPage({ params }: ChatPageProps): React.ReactElement {
  return <ConversationPageInner conversationId={params.id} />;
}
