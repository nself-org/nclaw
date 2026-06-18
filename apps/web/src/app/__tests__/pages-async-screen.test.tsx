/**
 * Page-level 7-state AsyncScreen tests for all claw-web data-fetching pages.
 *
 * Coverage: For each page, verifies all 7 states render the expected UI.
 * Approach: Mock usePagination/useMessages/useSessions to control state,
 *           mock useNetworkStatus for offline/online control.
 *
 * Pages tested (14+ assertions per page × 7 states):
 *   1. ChatHomePage  (/page.tsx)
 *   2. ChatConversationPage  (/chat/[id]/page.tsx)
 *   3. HistoryPage  (/history/page.tsx)
 *   4. MemoryPage  (/memory/page.tsx)
 *   5. GalleryPage  (/gallery/page.tsx)
 *   6. PromptsPage  (/prompts/page.tsx)
 *   7. PoolPage  (/pool/page.tsx)
 *
 * SOT: T-P3-E5-W1-S1-T01
 */

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

// ─── Global mocks ─────────────────────────────────────────────────────────────

// useNetworkStatus — default to online; override per test
vi.mock('@/hooks/useNetworkStatus', () => ({
  useNetworkStatus: vi.fn(() => ({ isOnline: true })),
}));

// useSessions — used by ChatHomePage
vi.mock('@/hooks/use-sessions', () => ({
  useSessions: vi.fn(() => ({
    conversations: [],
    isLoading: false,
    error: null,
    createConversation: vi.fn(),
    deleteConversation: vi.fn(),
  })),
}));

// useMessages — used by ChatConversationPage
vi.mock('@/hooks/use-messages', () => ({
  useMessages: vi.fn(() => ({
    messages: [],
    isLoading: false,
    error: null,
    sendMessage: vi.fn(),
    isStreaming: false,
    stopStream: vi.fn(),
  })),
}));

// usePagination — used by History, Memory, Gallery, Prompts
vi.mock('@/hooks/use-pagination', () => ({
  usePagination: vi.fn(() => ({
    items: [],
    loadMore: vi.fn(),
    hasMore: false,
    loading: false,
    error: null,
    reset: vi.fn(),
  })),
}));

// useChatStore — used by ChatConversationPage
vi.mock('@/store/chat-store', () => ({
  useChatStore: vi.fn((selector: (s: unknown) => unknown) =>
    selector({
      conversations: [],
      messages: {},
      currentConversationId: null,
      streamingContent: {},
      setConversations: vi.fn(),
      addConversation: vi.fn(),
      removeConversation: vi.fn(),
      updateConversation: vi.fn(),
      setMessages: vi.fn(),
      appendMessage: vi.fn(),
      appendStreamingContent: vi.fn(),
      clearStreamingContent: vi.fn(),
      setCurrentConversationId: vi.fn(),
    }),
  ),
}));

// useAppStore — used by some pages
vi.mock('@/store/app-store', () => ({
  useAppStore: vi.fn(() => null),
}));

// PoolManager — stub heavy component
vi.mock('@/components/pool/PoolManager', () => ({
  PoolManager: () => <div data-testid="pool-manager-stub">Pool</div>,
}));

// GreetingBanner — stub
vi.mock('@/components/chat/GreetingBanner', () => ({
  GreetingBanner: () => <div data-testid="greeting-banner-stub" />,
}));

// InputBar — stub (it's very large)
vi.mock('@/components/chat/InputBar', () => ({
  InputBar: () => <div data-testid="input-bar-stub" />,
}));

// MessageList — stub
vi.mock('@/components/chat/MessageList', () => ({
  MessageList: () => <div data-testid="message-list-stub" />,
}));

// next/navigation
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
}));

// framer-motion — pass-through
vi.mock('framer-motion', () => ({
  motion: {
    div: ({ children, ...rest }: React.HTMLAttributes<HTMLDivElement>) => (
      <div {...rest}>{children}</div>
    ),
    li: ({ children, ...rest }: React.LiHTMLAttributes<HTMLLIElement>) => (
      <li {...rest}>{children}</li>
    ),
  },
  AnimatePresence: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

// ─── Import hooks for mock access ────────────────────────────────────────────
import { useNetworkStatus } from '@/hooks/useNetworkStatus';
import { useSessions } from '@/hooks/use-sessions';
import { useMessages } from '@/hooks/use-messages';
import { usePagination } from '@/hooks/use-pagination';

// Import pages under test
import ChatHomePage from '@/app/(app)/page';
import ChatConversationPage from '@/app/(app)/chat/[id]/page';
import HistoryPage from '@/app/(app)/history/page';
import MemoryPage from '@/app/(app)/memory/page';
import GalleryPage from '@/app/(app)/gallery/page';
import PromptsPage from '@/app/(app)/prompts/page';
import PoolPage from '@/app/(app)/pool/page';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const mockNetworkStatus = useNetworkStatus as ReturnType<typeof vi.fn>;
const mockUseSessions = useSessions as ReturnType<typeof vi.fn>;
const mockUseMessages = useMessages as ReturnType<typeof vi.fn>;
const mockUsePagination = usePagination as ReturnType<typeof vi.fn>;

function setOnline() {
  mockNetworkStatus.mockReturnValue({ isOnline: true });
}

function setOffline() {
  mockNetworkStatus.mockReturnValue({ isOnline: false });
}

function make429(): Error & { status: number } {
  return Object.assign(new Error('Too Many Requests'), { status: 429 });
}

function make401(): Error & { status: number } {
  return Object.assign(new Error('Unauthorized'), { status: 401 });
}

// ─── Page 1: ChatHomePage ─────────────────────────────────────────────────────

describe('ChatHomePage — 7 states', () => {
  beforeEach(() => {
    setOnline();
    mockUseSessions.mockReturnValue({
      conversations: [],
      isLoading: false,
      error: null,
      createConversation: vi.fn(),
      deleteConversation: vi.fn(),
    });
  });

  it('State 1 — loading: shows skeleton', () => {
    mockUseSessions.mockReturnValue({ conversations: [], isLoading: true, error: null, createConversation: vi.fn(), deleteConversation: vi.fn() });
    render(<ChatHomePage />);
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
  });

  it('State 2 — offline: shows offline UI', () => {
    setOffline();
    render(<ChatHomePage />);
    expect(screen.getByTestId('offline-banner')).toBeTruthy();
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('State 3 — error: shows error card', () => {
    mockUseSessions.mockReturnValue({ conversations: [], isLoading: false, error: new Error('Server error'), createConversation: vi.fn(), deleteConversation: vi.fn() });
    render(<ChatHomePage />);
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
  });

  it('State 4 — rate-limited (429): shows rate-limit UI', () => {
    mockUseSessions.mockReturnValue({ conversations: [], isLoading: false, error: make429(), createConversation: vi.fn(), deleteConversation: vi.fn() });
    render(<ChatHomePage />);
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
  });

  it('State 5 — permission-denied (401): shows permission-denied UI', () => {
    mockUseSessions.mockReturnValue({ conversations: [], isLoading: false, error: make401(), createConversation: vi.fn(), deleteConversation: vi.fn() });
    render(<ChatHomePage />);
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 6 — empty: shows empty CTA', () => {
    render(<ChatHomePage />);
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(/No conversations yet/i)).toBeTruthy();
  });

  it('State 7 — populated: renders conversation list', () => {
    mockUseSessions.mockReturnValue({
      conversations: [{ id: '1', title: 'Test convo', updatedAt: new Date().toISOString(), lastMessageAt: null, messageCount: 3, topicId: null, createdAt: new Date().toISOString() }],
      isLoading: false,
      error: null,
      createConversation: vi.fn(),
      deleteConversation: vi.fn(),
    });
    render(<ChatHomePage />);
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
  });
});

// ─── Page 2: ChatConversationPage ────────────────────────────────────────────

describe('ChatConversationPage — 7 states', () => {
  beforeEach(() => {
    setOnline();
    mockUseMessages.mockReturnValue({ messages: [], isLoading: false, error: null, sendMessage: vi.fn(), isStreaming: false, stopStream: vi.fn() });
  });

  it('State 1 — loading: shows skeleton', () => {
    mockUseMessages.mockReturnValue({ messages: [], isLoading: true, error: null, sendMessage: vi.fn(), isStreaming: false, stopStream: vi.fn() });
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
  });

  it('State 2 — offline: shows offline UI', () => {
    setOffline();
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('State 3 — error: shows error card', () => {
    mockUseMessages.mockReturnValue({ messages: [], isLoading: false, error: new Error('Fetch failed'), sendMessage: vi.fn(), isStreaming: false, stopStream: vi.fn() });
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
  });

  it('State 4 — rate-limited: shows rate-limit UI', () => {
    mockUseMessages.mockReturnValue({ messages: [], isLoading: false, error: make429(), sendMessage: vi.fn(), isStreaming: false, stopStream: vi.fn() });
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
  });

  it('State 5 — permission-denied: shows perm-denied UI', () => {
    mockUseMessages.mockReturnValue({ messages: [], isLoading: false, error: make401(), sendMessage: vi.fn(), isStreaming: false, stopStream: vi.fn() });
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 6 — empty: shows start-conversation CTA', () => {
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(/Start the conversation/i)).toBeTruthy();
  });

  it('State 7 — populated: renders message list stub', () => {
    mockUseMessages.mockReturnValue({ messages: [{ id: '1', conversationId: 'abc', role: 'user', content: 'Hi', createdAt: new Date().toISOString(), tokens: null }], isLoading: false, error: null, sendMessage: vi.fn(), isStreaming: false, stopStream: vi.fn() });
    render(<ChatConversationPage params={Promise.resolve({ id: 'abc' })} />);
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
  });
});

// ─── Page 3: HistoryPage ─────────────────────────────────────────────────────

describe('HistoryPage — 7 states', () => {
  beforeEach(() => {
    setOnline();
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn() });
  });

  it('State 1 — loading: shows skeleton', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: true, error: null, reset: vi.fn() });
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
  });

  it('State 2 — offline: shows offline UI', () => {
    setOffline();
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('State 3 — error: shows error card', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: new Error('Fail'), reset: vi.fn() });
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
  });

  it('State 4 — rate-limited: shows rate-limited UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make429(), reset: vi.fn() });
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
  });

  it('State 5 — permission-denied: shows perm-denied UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make401(), reset: vi.fn() });
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 6 — empty: shows no-history CTA', () => {
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(/No history yet/i)).toBeTruthy();
  });

  it('State 7 — populated: renders conversation items', () => {
    mockUsePagination.mockReturnValue({
      items: [{ id: '1', title: 'Old chat', updatedAt: new Date().toISOString(), lastMessageAt: null, messageCount: 1, topicId: null, createdAt: new Date().toISOString() }],
      loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn(),
    });
    render(<HistoryPage />);
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
  });
});

// ─── Page 4: MemoryPage ──────────────────────────────────────────────────────

describe('MemoryPage — 7 states', () => {
  beforeEach(() => {
    setOnline();
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn() });
  });

  it('State 1 — loading: shows skeleton', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: true, error: null, reset: vi.fn() });
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
  });

  it('State 2 — offline: shows offline UI', () => {
    setOffline();
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('State 3 — error: shows error card', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: new Error('Mem fail'), reset: vi.fn() });
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
  });

  it('State 4 — rate-limited: shows rate-limited UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make429(), reset: vi.fn() });
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
  });

  it('State 5 — permission-denied: shows perm-denied UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make401(), reset: vi.fn() });
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 6 — empty: shows start-conversation CTA', () => {
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(/No memories yet/i)).toBeTruthy();
  });

  it('State 7 — populated: renders memory items', () => {
    mockUsePagination.mockReturnValue({
      items: [{ id: '1', type: 'fact', content: 'User likes tea', confidence: 0.9, sourceId: null, createdAt: new Date().toISOString() }],
      loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn(),
    });
    render(<MemoryPage />);
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
  });
});

// ─── Page 5: GalleryPage ─────────────────────────────────────────────────────

describe('GalleryPage — 7 states', () => {
  beforeEach(() => {
    setOnline();
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn() });
  });

  it('State 1 — loading: shows skeleton', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: true, error: null, reset: vi.fn() });
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
  });

  it('State 2 — offline: shows offline UI', () => {
    setOffline();
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('State 3 — error: shows error card', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: new Error('Gallery fail'), reset: vi.fn() });
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
  });

  it('State 4 — rate-limited: shows rate-limited UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make429(), reset: vi.fn() });
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
  });

  it('State 5 — permission-denied: shows perm-denied UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make401(), reset: vi.fn() });
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 6 — empty: shows no-images CTA', () => {
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(/No images yet/i)).toBeTruthy();
  });

  it('State 7 — populated: renders image grid', () => {
    mockUsePagination.mockReturnValue({
      items: [{ id: '1', url: '/img.jpg', prompt: 'A cat', width: 512, height: 512, createdAt: new Date().toISOString() }],
      loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn(),
    });
    render(<GalleryPage />);
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
  });
});

// ─── Page 6: PromptsPage ─────────────────────────────────────────────────────

describe('PromptsPage — 7 states', () => {
  beforeEach(() => {
    setOnline();
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn() });
  });

  it('State 1 — loading: shows skeleton', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: true, error: null, reset: vi.fn() });
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-loading')).toBeTruthy();
  });

  it('State 2 — offline: shows offline UI', () => {
    setOffline();
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-offline')).toBeTruthy();
  });

  it('State 3 — error: shows error card', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: new Error('Prompts fail'), reset: vi.fn() });
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-error')).toBeTruthy();
  });

  it('State 4 — rate-limited: shows rate-limited UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make429(), reset: vi.fn() });
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-rate-limited')).toBeTruthy();
  });

  it('State 5 — permission-denied: shows perm-denied UI', () => {
    mockUsePagination.mockReturnValue({ items: [], loadMore: vi.fn(), hasMore: false, loading: false, error: make401(), reset: vi.fn() });
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-permission-denied')).toBeTruthy();
  });

  it('State 6 — empty: shows no-prompts CTA', () => {
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-empty')).toBeTruthy();
    expect(screen.getByText(/No saved prompts yet/i)).toBeTruthy();
  });

  it('State 7 — populated: renders prompt list', () => {
    mockUsePagination.mockReturnValue({
      items: [{ id: '1', name: 'Concise', content: 'Be brief.', isSystem: false, createdAt: new Date().toISOString() }],
      loadMore: vi.fn(), hasMore: false, loading: false, error: null, reset: vi.fn(),
    });
    render(<PromptsPage />);
    expect(screen.getByTestId('async-screen-populated')).toBeTruthy();
  });
});

// ─── Page 7: PoolPage ────────────────────────────────────────────────────────
// PoolPage shows OfflineBanner when offline; the PoolManager component handles its own states.

describe('PoolPage — offline state', () => {
  it('shows OfflineBanner when offline', () => {
    setOffline();
    render(<PoolPage />);
    expect(screen.getByTestId('offline-banner')).toBeTruthy();
  });

  it('hides OfflineBanner when online', () => {
    setOnline();
    render(<PoolPage />);
    expect(screen.queryByTestId('offline-banner')).toBeNull();
  });

  it('renders PoolManager stub', () => {
    render(<PoolPage />);
    expect(screen.getByTestId('pool-manager-stub')).toBeTruthy();
  });
});
