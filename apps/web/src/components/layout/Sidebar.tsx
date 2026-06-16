'use client';

import { useCallback, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useQuery } from '@tanstack/react-query';
import { AnimatePresence, motion } from 'framer-motion';
import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  FolderOpen,
  LogOut,
  MessageSquarePlus,
  Search,
  Settings,
} from 'lucide-react';
import { useAppStore } from '@/store/app-store';
import { useChatStore } from '@/store/chat-store';
import api from '@/lib/api';
import type { Conversation, Topic } from '@/types';

// ---------------------------------------------------------------------------
// Skeleton helpers
// ---------------------------------------------------------------------------

function SkeletonLine({ width = 'w-full', height = 'h-3' }: { width?: string; height?: string }) {
  return (
    <div
      className={`${width} ${height} rounded`}
      style={{ animation: 'skeleton-pulse 1.5s ease infinite', background: 'rgba(255,255,255,0.06)' }}
    />
  );
}

function SidebarSkeleton() {
  return (
    <div className="flex flex-col gap-3 px-3 pt-2" role="status" aria-label="Loading topics">
      {[0, 1, 2].map((i) => (
        <div key={i} className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <SkeletonLine width="w-4" height="h-4" />
            <SkeletonLine width="w-28" />
          </div>
          {[0, 1].map((j) => (
            <div key={j} className="ml-6">
              <SkeletonLine width="w-40" />
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Conversation item
// ---------------------------------------------------------------------------

interface ConversationItemProps {
  conv: Conversation;
  isActive: boolean;
  collapsed: boolean;
  onSelect: (id: string) => void;
  tabIndex: number;
  itemRef: (el: HTMLButtonElement | null) => void;
}

function ConversationItem({
  conv,
  isActive,
  collapsed,
  onSelect,
  tabIndex,
  itemRef,
}: ConversationItemProps) {
  if (collapsed) return null;

  return (
    <button
      ref={itemRef}
      type="button"
      tabIndex={tabIndex}
      onClick={() => onSelect(conv.id)}
      aria-current={isActive ? 'page' : undefined}
      className="group w-full text-left flex items-center gap-2 px-3 py-1.5 rounded-md text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)] focus-visible:ring-offset-1 focus-visible:ring-offset-[var(--color-bg)]"
      style={{
        color: isActive ? 'var(--color-primary-text)' : 'var(--color-text-muted)',
        background: isActive ? 'rgba(99,102,241,0.10)' : 'transparent',
        borderLeft: isActive ? '2px solid var(--color-primary)' : '2px solid transparent',
        paddingLeft: isActive ? '10px' : '12px',
      }}
      onMouseEnter={(e) => {
        if (!isActive) {
          (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.04)';
          (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text)';
        }
      }}
      onMouseLeave={(e) => {
        if (!isActive) {
          (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
          (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text-muted)';
        }
      }}
    >
      <span className="truncate flex-1 min-w-0">{conv.title || 'Untitled conversation'}</span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// Topic section
// ---------------------------------------------------------------------------

interface TopicSectionProps {
  topic: Topic | null; // null = uncategorized
  conversations: Conversation[];
  currentConversationId: string | null;
  collapsed: boolean;
  initiallyOpen?: boolean;
  onSelect: (id: string) => void;
  focusedIndex: number;
  flatItems: FlatItem[];
}

interface FlatItem {
  convId: string;
  ref: (el: HTMLButtonElement | null) => void;
}

function TopicSection({
  topic,
  conversations,
  currentConversationId,
  collapsed,
  initiallyOpen = true,
  onSelect,
  focusedIndex,
  flatItems,
}: TopicSectionProps) {
  const [open, setOpen] = useState(initiallyOpen);
  const label = topic ? topic.name : 'Uncategorized';
  const count = conversations.length;

  if (count === 0) return null;

  return (
    <div>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="w-full flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-semibold uppercase tracking-wider transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)] focus-visible:ring-offset-1 focus-visible:ring-offset-[var(--color-bg)]"
        style={{ color: 'var(--color-text-muted)' }}
        onMouseEnter={(e) => {
          (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.04)';
        }}
        onMouseLeave={(e) => {
          (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
        }}
        title={collapsed ? label : undefined}
      >
        {collapsed ? (
          <FolderOpen size={16} style={{ color: 'var(--color-text-muted)', flexShrink: 0 }} />
        ) : (
          <>
            <motion.span
              animate={{ rotate: open ? 0 : -90 }}
              transition={{ duration: 0.18, ease: 'easeOut' }}
              className="flex items-center"
            >
              <ChevronDown size={14} style={{ flexShrink: 0 }} />
            </motion.span>
            <span className="truncate flex-1 min-w-0 text-left">{label}</span>
            <span
              className="ml-auto flex-shrink-0 text-xs px-1.5 py-0.5 rounded-full font-mono"
              style={{ background: 'rgba(255,255,255,0.07)', color: 'var(--color-text-muted)' }}
            >
              {count}
            </span>
          </>
        )}
      </button>

      {!collapsed && (
        <AnimatePresence initial={false}>
          {open && (
            <motion.div
              key="conversations"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.22, ease: 'easeOut' }}
              style={{ overflow: 'hidden' }}
            >
              <div className="flex flex-col gap-0.5 pl-3 mt-0.5 mb-1">
                {conversations.map((conv) => {
                  const flatIdx = flatItems.findIndex((fi) => fi.convId === conv.id);
                  return (
                    <ConversationItem
                      key={conv.id}
                      conv={conv}
                      isActive={conv.id === currentConversationId}
                      collapsed={false}
                      onSelect={onSelect}
                      tabIndex={focusedIndex === flatIdx ? 0 : -1}
                      itemRef={flatIdx >= 0 ? flatItems[flatIdx].ref : () => undefined}
                    />
                  );
                })}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// User avatar
// ---------------------------------------------------------------------------

function UserAvatar({ url, name }: { url: string | null; name: string }) {
  if (url) {
    return (
      <img
        src={url}
        alt={name}
        className="w-7 h-7 rounded-full object-cover flex-shrink-0"
        style={{ border: '1px solid var(--color-border)' }}
      />
    );
  }
  const initials = name
    .split(' ')
    .slice(0, 2)
    .map((s) => s[0] ?? '')
    .join('')
    .toUpperCase();
  return (
    <div
      className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0 text-xs font-semibold"
      style={{
        background: 'var(--color-primary)',
        color: '#fff',
        border: '1px solid var(--color-border)',
      }}
      aria-hidden="true"
    >
      {initials}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main Sidebar
// ---------------------------------------------------------------------------

export function Sidebar() {
  const router = useRouter();
  const { user, settings, sidebarCollapsed, setSidebarCollapsed, signOut } = useAppStore();
  const {
    conversations,
    topics,
    currentConversationId,
    searchQuery,
    setConversations,
    setTopics,
    setCurrentConversationId,
    setSearchQuery,
  } = useChatStore();

  const displayName =
    settings?.displayName ?? user?.displayName ?? user?.email ?? 'You';

  // Data fetching
  const {
    isLoading: topicsLoading,
    isError: topicsError,
    refetch: refetchTopics,
  } = useQuery({
    queryKey: ['topics-tree'],
    queryFn: async () => {
      const r = await api.getTopicTree();
      if (!r.ok) throw new Error(r.error.message);
      setTopics(r.value);
      return r.value;
    },
    staleTime: 60_000,
  });

  const {
    isLoading: convsLoading,
    isError: convsError,
    refetch: refetchConvs,
  } = useQuery({
    queryKey: ['conversations', currentConversationId],
    queryFn: async () => {
      const r = await api.listConversations(1, 100);
      if (!r.ok) throw new Error(r.error.message);
      setConversations(r.value.data);
      return r.value.data;
    },
    staleTime: 30_000,
  });

  const isLoading = topicsLoading || convsLoading;
  const isError = topicsError || convsError;

  const handleRetry = useCallback(() => {
    void refetchTopics();
    void refetchConvs();
  }, [refetchTopics, refetchConvs]);

  // New conversation
  const handleNewConversation = useCallback(async () => {
    const r = await api.createConversation();
    if (!r.ok) return; // silently ignore — user can retry
    setCurrentConversationId(r.value.id);
    router.push(`/chat/${r.value.id}`);
  }, [router, setCurrentConversationId]);

  const handleSelectConversation = useCallback(
    (id: string) => {
      setCurrentConversationId(id);
      router.push(`/chat/${id}`);
    },
    [router, setCurrentConversationId]
  );

  const handleSignOut = useCallback(async () => {
    await api.signOut(); // Result — ignore failure, always sign out locally
    signOut();
    router.push('/signin');
  }, [router, signOut]);

  // Search filtering
  const q = searchQuery.trim().toLowerCase();
  const filteredConversations = q
    ? conversations.filter((c) => c.title.toLowerCase().includes(q))
    : conversations;

  // Group conversations by topic
  const topicMap = new Map<string, Topic>(topics.map((t) => [t.id, t]));

  // Sort topics by updatedAt desc
  const sortedTopics = [...topics].sort(
    (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
  );

  const conversationsByTopic = new Map<string | null, Conversation[]>();
  conversationsByTopic.set(null, []);
  for (const t of sortedTopics) {
    conversationsByTopic.set(t.id, []);
  }

  const sorted = [...filteredConversations].sort((a, b) => {
    const ta = a.lastMessageAt ?? a.updatedAt;
    const tb = b.lastMessageAt ?? b.updatedAt;
    return new Date(tb).getTime() - new Date(ta).getTime();
  });

  for (const conv of sorted) {
    const key = conv.topicId && topicMap.has(conv.topicId) ? conv.topicId : null;
    const bucket = conversationsByTopic.get(key) ?? [];
    bucket.push(conv);
    conversationsByTopic.set(key, bucket);
  }

  // Flat list for keyboard navigation
  const flatItemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const [focusedIndex, setFocusedIndex] = useState(-1);

  const flatConvs: string[] = [];
  for (const t of sortedTopics) {
    const bucket = conversationsByTopic.get(t.id) ?? [];
    for (const c of bucket) flatConvs.push(c.id);
  }
  const uncategorized = conversationsByTopic.get(null) ?? [];
  for (const c of uncategorized) flatConvs.push(c.id);

  // Resize refs array when flat list changes
  if (flatItemRefs.current.length !== flatConvs.length) {
    flatItemRefs.current = flatConvs.map((_, i) => flatItemRefs.current[i] ?? null);
  }

  const flatItems: FlatItem[] = flatConvs.map((convId, i) => ({
    convId,
    ref: (el: HTMLButtonElement | null) => {
      flatItemRefs.current[i] = el;
    },
  }));

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (flatConvs.length === 0) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const next = Math.min(focusedIndex + 1, flatConvs.length - 1);
        setFocusedIndex(next);
        flatItemRefs.current[next]?.focus();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prev = Math.max(focusedIndex - 1, 0);
        setFocusedIndex(prev);
        flatItemRefs.current[prev]?.focus();
      } else if (e.key === 'Enter' || e.key === ' ') {
        if (focusedIndex >= 0 && focusedIndex < flatConvs.length) {
          e.preventDefault();
          handleSelectConversation(flatConvs[focusedIndex]);
        }
      }
    },
    [flatConvs, focusedIndex, handleSelectConversation]
  );

  const W_EXPANDED = 280;
  const W_COLLAPSED = 48;

  // ---------------------------------------------------------------------------
  // Collapsed strip
  // ---------------------------------------------------------------------------

  if (sidebarCollapsed) {
    return (
      <motion.aside
        key="collapsed"
        initial={{ width: W_EXPANDED }}
        animate={{ width: W_COLLAPSED }}
        transition={{ duration: 0.25, ease: 'easeInOut' }}
        className="flex flex-col items-center gap-2 py-3 flex-shrink-0 h-screen relative"
        style={{
          background: '#13131F',
          borderRight: '1px solid var(--color-border)',
          width: W_COLLAPSED,
        }}
        aria-label="Sidebar (collapsed)"
      >
        {/* Expand toggle */}
        <button
          type="button"
          onClick={() => setSidebarCollapsed(false)}
          aria-label="Expand sidebar"
          title="Expand sidebar"
          className="absolute -right-3 top-5 z-10 w-6 h-6 rounded-full flex items-center justify-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
          style={{
            background: '#13131F',
            border: '1px solid var(--color-border)',
            color: 'var(--color-text-muted)',
          }}
        >
          <ChevronRight size={13} />
        </button>

        {/* New conversation */}
        <button
          type="button"
          onClick={() => void handleNewConversation()}
          aria-label="New conversation"
          title="New conversation"
          className="w-9 h-9 rounded-lg flex items-center justify-center transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
          style={{ color: 'var(--color-text-muted)' }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.07)';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text-muted)';
          }}
        >
          <MessageSquarePlus size={18} />
        </button>

        {/* Search */}
        <button
          type="button"
          aria-label="Search conversations"
          title="Search conversations"
          className="w-9 h-9 rounded-lg flex items-center justify-center transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
          style={{ color: 'var(--color-text-muted)' }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.07)';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text-muted)';
          }}
          onClick={() => setSidebarCollapsed(false)}
        >
          <Search size={18} />
        </button>

        <div className="flex-1" />

        {/* Settings */}
        <Link
          href="/settings"
          aria-label="Settings"
          title="Settings"
          className="w-9 h-9 rounded-lg flex items-center justify-center transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
          style={{ color: 'var(--color-text-muted)' }}
        >
          <Settings size={18} />
        </Link>

        {/* Sign out */}
        <button
          type="button"
          onClick={() => void handleSignOut()}
          aria-label="Sign out"
          title="Sign out"
          className="w-9 h-9 rounded-lg flex items-center justify-center transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
          style={{ color: 'var(--color-text-muted)' }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(255,255,255,0.07)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
          }}
        >
          <LogOut size={18} />
        </button>
      </motion.aside>
    );
  }

  // ---------------------------------------------------------------------------
  // Expanded sidebar
  // ---------------------------------------------------------------------------

  return (
    <motion.aside
      key="expanded"
      initial={{ width: W_COLLAPSED }}
      animate={{ width: W_EXPANDED }}
      transition={{ duration: 0.25, ease: 'easeInOut' }}
      className="flex flex-col flex-shrink-0 h-screen relative"
      style={{
        background: '#13131F',
        borderRight: '1px solid var(--color-border)',
        width: W_EXPANDED,
      }}
      aria-label="Sidebar"
    >
      {/* Collapse toggle */}
      <button
        type="button"
        onClick={() => setSidebarCollapsed(true)}
        aria-label="Collapse sidebar"
        title="Collapse sidebar"
        className="absolute -right-3 top-5 z-10 w-6 h-6 rounded-full flex items-center justify-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
        style={{
          background: '#13131F',
          border: '1px solid var(--color-border)',
          color: 'var(--color-text-muted)',
        }}
      >
        <ChevronLeft size={13} />
      </button>

      {/* Header */}
      <div
        className="flex-shrink-0 px-4 pt-4 pb-3"
        style={{ borderBottom: '1px solid var(--color-border)' }}
      >
        {/* Logo */}
        <div className="flex items-center mb-3">
          <span
            className="text-lg font-semibold select-none"
            style={{ color: 'var(--color-primary-text)' }}
          >
            ɳClaw
          </span>
        </div>

        {/* New conversation button */}
        <button
          type="button"
          onClick={() => void handleNewConversation()}
          className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)] mb-2"
          style={{
            background: 'rgba(99,102,241,0.12)',
            color: 'var(--color-primary-text)',
            border: '1px solid rgba(99,102,241,0.25)',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(99,102,241,0.20)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(99,102,241,0.12)';
          }}
        >
          <MessageSquarePlus size={15} aria-hidden="true" />
          New conversation
        </button>

        {/* Search */}
        <div className="relative">
          <Search
            size={14}
            className="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
            style={{ color: 'var(--color-text-muted)' }}
            aria-hidden="true"
          />
          <input
            type="search"
            placeholder="Search conversations…"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            aria-label="Search conversations"
            className="w-full pl-8 pr-3 py-1.5 rounded-lg text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
            style={{
              background: 'var(--color-bg-input)',
              border: '1px solid var(--color-border)',
              color: 'var(--color-text)',
            }}
          />
        </div>
      </div>

      {/* Topic tree */}
      <div
        className="flex-1 overflow-y-auto py-2 flex flex-col gap-1"
        role="navigation"
        aria-label="Conversations"
        onKeyDown={handleKeyDown}
      >
        {isLoading && <SidebarSkeleton />}

        {!isLoading && isError && (
          <div className="px-4 py-6 flex flex-col items-center gap-3 text-center">
            <p className="text-sm" style={{ color: 'var(--color-text-muted)' }}>
              Could not load topics — tap to retry
            </p>
            <button
              type="button"
              onClick={handleRetry}
              className="text-sm px-3 py-1.5 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]"
              style={{
                background: 'rgba(99,102,241,0.15)',
                color: 'var(--color-primary-text)',
                border: '1px solid rgba(99,102,241,0.3)',
              }}
            >
              Retry
            </button>
          </div>
        )}

        {!isLoading && !isError && conversations.length === 0 && (
          <div className="px-4 py-6 text-center">
            <p className="text-sm" style={{ color: 'var(--color-text-muted)' }}>
              No conversations yet — start one above
            </p>
          </div>
        )}

        {!isLoading && !isError && conversations.length > 0 && (
          <div className="flex flex-col gap-1 px-2">
            {sortedTopics.map((topic) => {
              const bucket = conversationsByTopic.get(topic.id) ?? [];
              return (
                <TopicSection
                  key={topic.id}
                  topic={topic}
                  conversations={bucket}
                  currentConversationId={currentConversationId}
                  collapsed={false}
                  initiallyOpen={true}
                  onSelect={handleSelectConversation}
                  focusedIndex={focusedIndex}
                  flatItems={flatItems}
                />
              );
            })}

            {(conversationsByTopic.get(null) ?? []).length > 0 && (
              <TopicSection
                key="__uncategorized__"
                topic={null}
                conversations={conversationsByTopic.get(null) ?? []}
                currentConversationId={currentConversationId}
                collapsed={false}
                initiallyOpen={true}
                onSelect={handleSelectConversation}
                focusedIndex={focusedIndex}
                flatItems={flatItems}
              />
            )}
          </div>
        )}
      </div>

      {/* Footer */}
      <div
        className="flex-shrink-0 px-3 py-3 flex items-center gap-2"
        style={{ borderTop: '1px solid var(--color-border)' }}
      >
        <UserAvatar url={settings?.avatarUrl ?? user?.avatarUrl ?? null} name={displayName} />
        <span
          className="flex-1 text-sm font-medium truncate min-w-0"
          style={{ color: 'var(--color-text)' }}
        >
          {displayName}
        </span>
        <Link
          href="/settings"
          aria-label="Settings"
          title="Settings"
          className="w-7 h-7 flex items-center justify-center rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)] flex-shrink-0"
          style={{ color: 'var(--color-text-muted)' }}
        >
          <Settings size={15} />
        </Link>
        <button
          type="button"
          onClick={() => void handleSignOut()}
          aria-label="Sign out"
          title="Sign out"
          className="w-7 h-7 flex items-center justify-center rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)] flex-shrink-0"
          style={{ color: 'var(--color-text-muted)' }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-error)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--color-text-muted)';
          }}
        >
          <LogOut size={15} />
        </button>
      </div>
    </motion.aside>
  );
}
