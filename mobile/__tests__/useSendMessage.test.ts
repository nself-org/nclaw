/**
 * Unit tests — useSendMessage hook (T04: backend wiring).
 *
 * Purpose: Verify all status transitions (idle → recalling → sending → sent | failed),
 *          typed ChatError classification (NetworkError, InferenceError, RateLimitError),
 *          optimistic UI callbacks, GraphQL persist, retry logic, and offline queue wiring.
 *
 * Inputs:  Mocked @nself/native-bridge getNcLawJSI().chatSend
 *          Mocked urql useMutation
 *          Mocked useMemoryRecall, useMemoryInsert, useAmbientContext
 *
 * Outputs: Assertions on all status transitions, callback invocations, and error states.
 *
 * Constraints: Uses renderHook + act from @testing-library/react-native.
 *              All mocks are reset in beforeEach.
 *              100% coverage of MessageStatus transitions (idle, recalling, sending, sent, failed).
 *              classifyChatError and generateId are tested directly as exported helpers.
 */

import { renderHook, act } from '@testing-library/react-native';
import type { ChatError, ChatMessage, MessageStatus } from '../types/chat';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

// Mock @nself/native-bridge — NativeNclaw.chatSend(message: string): Promise<string>
const mockChatSend = jest.fn<Promise<string>, [string]>();

jest.mock('@nself/native-bridge', () => ({
  NativeNclaw: {
    chatSend: mockChatSend,
    memorySearch: jest.fn().mockResolvedValue('[]'),
    memoryInsert: jest.fn().mockResolvedValue(undefined),
  },
}));

// Mock urql useMutation
const mockMutate = jest.fn<
  Promise<{ data: unknown; error: unknown }>,
  [unknown, unknown?]
>();
jest.mock('urql', () => ({
  useMutation: () => [{ fetching: false }, mockMutate],
}));

// Mock memory hooks
const mockRecallForQuery = jest.fn<Promise<string | null>, [string]>();
jest.mock('../hooks/useMemoryRecall', () => ({
  useMemoryRecall: () => ({
    recall: null,
    isRecalling: false,
    error: null,
    recallForQuery: mockRecallForQuery,
  }),
}));

const mockInsertMemory = jest.fn<Promise<void>, [unknown]>();
jest.mock('../hooks/useMemoryInsert', () => ({
  useMemoryInsert: () => ({
    insertMemory: mockInsertMemory,
    isInserting: false,
    error: null,
  }),
}));

// Mock ambient context (disabled by default)
jest.mock('../hooks/useAmbientContext', () => ({
  useAmbientContext: () => ({
    context: null,
    isActive: false,
    error: null,
    getContextBlock: () => null,
  }),
}));

// Mock services/chat to avoid gql parsing
jest.mock('../services/chat', () => ({
  PERSIST_USER_MESSAGE: 'PERSIST_USER_MESSAGE',
  OFFLINE_REQUEST_POLICY: 'network-only',
}));

// Import after mocks are registered
import { useSendMessage, classifyChatError, generateId } from '../hooks/useSendMessage';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** NativeNclaw.chatSend() returns the AI response string (T03 contract). */
const OK_AI_RESPONSE = 'Hello! How can I help you today?';

const OK_MUTATION_RESULT = {
  data: { insert_nclaw_messages_one: { id: 'msg-456' } },
  error: undefined,
};

function makeOptions(overrides: Partial<Parameters<typeof useSendMessage>[0]> = {}) {
  return {
    conversationId: 'conv-123',
    onNewConversation: jest.fn<void, [string]>(),
    onOptimisticMessage: jest.fn<void, [ChatMessage]>(),
    onMessageStatusChange: jest.fn<void, [string, MessageStatus]>(),
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  jest.useFakeTimers();
  mockChatSend.mockReset();
  mockMutate.mockReset();
  mockRecallForQuery.mockReset();
  mockInsertMemory.mockReset();

  // Default: recall returns null, chatSend succeeds, mutation succeeds
  mockRecallForQuery.mockResolvedValue(null);
  mockChatSend.mockResolvedValue(OK_AI_RESPONSE);
  mockMutate.mockResolvedValue(OK_MUTATION_RESULT);
});

afterEach(() => {
  jest.useRealTimers();
});

// ---------------------------------------------------------------------------
// classifyChatError — direct unit tests
// ---------------------------------------------------------------------------

describe('classifyChatError', () => {
  it('classifies rate_limit keyword as RateLimitError', () => {
    const err = classifyChatError(new Error('Request rate_limit exceeded'));
    expect(err.kind).toBe('RateLimitError');
    if (err.kind === 'RateLimitError') {
      expect(err.retryAfterMs).toBe(5000);
    }
  });

  it('classifies "rate limit" (with space) as RateLimitError', () => {
    const err = classifyChatError(new Error('You have hit the rate limit'));
    expect(err.kind).toBe('RateLimitError');
  });

  it('classifies [Network] prefix as NetworkError', () => {
    const err = classifyChatError(new Error('[Network] GraphQL persist failed'));
    expect(err.kind).toBe('NetworkError');
  });

  it('classifies ECONNREFUSED as NetworkError', () => {
    const err = classifyChatError(new Error('connect ECONNREFUSED 127.0.0.1:8080'));
    expect(err.kind).toBe('NetworkError');
  });

  it('classifies ETIMEDOUT as NetworkError', () => {
    const err = classifyChatError(new Error('socket hang up ETIMEDOUT'));
    expect(err.kind).toBe('NetworkError');
  });

  it('classifies unknown errors as InferenceError', () => {
    const err = classifyChatError(new Error('Model context overflow: too many tokens'));
    expect(err.kind).toBe('InferenceError');
  });

  it('extracts code from InferenceError message when present', () => {
    const err = classifyChatError(new Error('code=CONTEXT_OVERFLOW internal error'));
    expect(err.kind).toBe('InferenceError');
    if (err.kind === 'InferenceError') {
      expect(err.code).toBe('CONTEXT_OVERFLOW');
    }
  });

  it('uses "unknown" code when no code pattern in InferenceError', () => {
    const err = classifyChatError(new Error('something unexpected'));
    expect(err.kind).toBe('InferenceError');
    if (err.kind === 'InferenceError') {
      expect(err.code).toBe('unknown');
    }
  });

  it('handles non-Error thrown values', () => {
    const err = classifyChatError('plain string error');
    expect(err.kind).toBe('InferenceError');
  });
});

// ---------------------------------------------------------------------------
// generateId — direct unit test
// ---------------------------------------------------------------------------

describe('generateId', () => {
  it('returns a UUID v4 format string', () => {
    const id = generateId();
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it('generates unique IDs on each call', () => {
    const ids = new Set(Array.from({ length: 10 }, generateId));
    expect(ids.size).toBe(10);
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — status transition tests
// ---------------------------------------------------------------------------

describe('useSendMessage — status transitions', () => {
  it('initial status is idle', () => {
    const { result } = renderHook(() => useSendMessage(makeOptions()));
    expect(result.current.status).toBe('idle');
    expect(result.current.isSending).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('transitions idle → recalling → sending → sent on success', async () => {
    const statuses: string[] = [];

    // Capture status transitions via a slow recall
    let resolveRecall!: (v: string | null) => void;
    mockRecallForQuery.mockReturnValue(
      new Promise((res) => {
        resolveRecall = res;
      }),
    );

    let resolveChatSend!: (v: string) => void;
    mockChatSend.mockReturnValue(
      new Promise((res) => {
        resolveChatSend = res;
      }),
    );

    const { result } = renderHook(() => useSendMessage(makeOptions()));

    // Start send
    act(() => {
      result.current.sendMessage('hello world');
    });

    // After recall starts: should be 'recalling'
    expect(result.current.status).toBe('recalling');
    expect(result.current.isSending).toBe(true);
    statuses.push(result.current.status);

    // Resolve recall → should move to 'sending'
    await act(async () => {
      resolveRecall(null);
    });
    expect(result.current.status).toBe('sending');
    statuses.push(result.current.status);

    // Resolve chatSend + mutation → should move to 'sent'
    await act(async () => {
      resolveChatSend(OK_AI_RESPONSE);
    });
    expect(result.current.status).toBe('sent');
    statuses.push(result.current.status);

    expect(result.current.isSending).toBe(false);
    expect(result.current.error).toBeNull();
    expect(statuses).toEqual(['recalling', 'sending', 'sent']);
  });

  it('transitions to failed on InferenceError', async () => {
    mockChatSend.mockRejectedValue(new Error('Model crashed: context overflow'));

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('crash me');
    });

    expect(result.current.status).toBe('failed');
    expect(result.current.isSending).toBe(false);
    expect(result.current.error?.kind).toBe('InferenceError');
    expect(opts.onMessageStatusChange).toHaveBeenCalledWith(expect.any(String), 'failed');
  });

  it('transitions to failed on RateLimitError (no retry)', async () => {
    mockChatSend.mockRejectedValue(new Error('rate_limit: too many requests'));

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('ratelimited');
    });

    expect(result.current.status).toBe('failed');
    expect(result.current.error?.kind).toBe('RateLimitError');
    // Rate limit is not retried automatically
    expect(mockChatSend).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — optimistic UI tests
// ---------------------------------------------------------------------------

describe('useSendMessage — optimistic UI', () => {
  it('calls onOptimisticMessage immediately with sending status', async () => {
    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('test message');
    });

    expect(opts.onOptimisticMessage).toHaveBeenCalledTimes(1);
    const msg: ChatMessage = opts.onOptimisticMessage.mock.calls[0]![0] as ChatMessage;
    expect(msg.role).toBe('user');
    expect(msg.content).toBe('test message');
    expect(msg.status).toBe('sending');
  });

  it('calls onMessageStatusChange with sent on success', async () => {
    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('success test');
    });

    expect(opts.onMessageStatusChange).toHaveBeenCalledWith(expect.any(String), 'sent');
  });

  it('calls onMessageStatusChange with failed on InferenceError', async () => {
    mockChatSend.mockRejectedValue(new Error('inference error'));
    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('fail test');
    });

    expect(opts.onMessageStatusChange).toHaveBeenCalledWith(expect.any(String), 'failed');
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — NetworkError retry tests
// ---------------------------------------------------------------------------

describe('useSendMessage — NetworkError retry', () => {
  it('retries up to MAX_NETWORK_RETRIES times then surfaces failed', async () => {
    mockChatSend.mockRejectedValue(new Error('[Network] connection lost'));

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    const sendPromise = act(async () => {
      await result.current.sendMessage('retry test');
    });

    // Advance timers through all backoff delays (1s + 2s = 3 attempts total)
    await act(async () => {
      jest.advanceTimersByTime(1000); // attempt 2 backoff
    });
    await act(async () => {
      jest.advanceTimersByTime(2000); // attempt 3 backoff
    });

    await sendPromise;

    // chatSend called 3 times (attempt 1, 2, 3)
    expect(mockChatSend).toHaveBeenCalledTimes(3);
    expect(result.current.status).toBe('failed');
    expect(result.current.error?.kind).toBe('NetworkError');
  });

  it('does not retry InferenceError (no backoff)', async () => {
    mockChatSend.mockRejectedValue(new Error('code=CONTEXT_OVERFLOW inference failed'));

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('inference fail');
    });

    // Only called once — no retry for InferenceError
    expect(mockChatSend).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — retryLast tests
// ---------------------------------------------------------------------------

describe('useSendMessage — retryLast', () => {
  it('retryLast is a no-op when no prior send has been made', async () => {
    const { result } = renderHook(() => useSendMessage(makeOptions()));

    await act(async () => {
      await result.current.retryLast();
    });

    expect(mockChatSend).not.toHaveBeenCalled();
  });

  it('retryLast re-sends the last text after a failed send', async () => {
    mockChatSend
      .mockRejectedValueOnce(new Error('inference failed'))
      .mockResolvedValueOnce(OK_AI_RESPONSE);

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    // First send fails
    await act(async () => {
      await result.current.sendMessage('retry me');
    });
    expect(result.current.status).toBe('failed');

    // Retry succeeds
    await act(async () => {
      await result.current.retryLast();
    });
    expect(result.current.status).toBe('sent');
    expect(mockChatSend).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — new conversation tests
// ---------------------------------------------------------------------------

describe('useSendMessage — new conversation', () => {
  it('calls onNewConversation with a generated UUID when conversationId was null', async () => {
    // chatSend returns a string — conversationId is generated client-side by useSendMessage
    mockChatSend.mockResolvedValue(OK_AI_RESPONSE);

    const opts = makeOptions({ conversationId: null });
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('start new conversation');
    });

    // onNewConversation called with a UUID v4-format string
    expect(opts.onNewConversation).toHaveBeenCalledTimes(1);
    const calledWith = (opts.onNewConversation as jest.Mock).mock.calls[0][0] as string;
    expect(calledWith).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it('does NOT call onNewConversation when conversationId is already set', async () => {
    const opts = makeOptions({ conversationId: 'existing-conv' });
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('continue existing');
    });

    expect(opts.onNewConversation).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — guard: no concurrent sends
// ---------------------------------------------------------------------------

describe('useSendMessage — concurrency guard', () => {
  it('does not start a second send while one is in-flight', async () => {
    // First send is slow
    let resolveFirst!: (v: string) => void;
    mockChatSend
      .mockReturnValueOnce(
        new Promise((res) => {
          resolveFirst = res;
        }),
      )
      .mockResolvedValue(OK_AI_RESPONSE);

    const { result } = renderHook(() => useSendMessage(makeOptions()));

    // Start first send (don't await yet)
    act(() => {
      result.current.sendMessage('first');
    });

    // Attempt second send while first is in-flight — should be ignored
    await act(async () => {
      await result.current.sendMessage('second');
    });

    // Only one chatSend call (second was swallowed by the guard)
    await act(async () => {
      resolveFirst(OK_AI_RESPONSE);
    });

    expect(mockChatSend).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — empty text guard
// ---------------------------------------------------------------------------

describe('useSendMessage — empty text guard', () => {
  it('does not send when text is empty or whitespace-only', async () => {
    const { result } = renderHook(() => useSendMessage(makeOptions()));

    await act(async () => {
      await result.current.sendMessage('   ');
    });

    expect(mockChatSend).not.toHaveBeenCalled();
    expect(result.current.status).toBe('idle');
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — memory context injection
// ---------------------------------------------------------------------------

describe('useSendMessage — memory context injection', () => {
  it('augments the prompt with memory context when recall returns non-null', async () => {
    mockRecallForQuery.mockResolvedValue('<memory_context>\n[1] user prefers TypeScript\n</memory_context>');

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    await act(async () => {
      await result.current.sendMessage('what language do I prefer?');
    });

    // chatSend receives the augmented prompt with memory context prepended
    expect(mockChatSend).toHaveBeenCalledWith(
      expect.stringContaining('<memory_context>'),
      expect.anything(),
      expect.anything(),
    );
  });
});

// ---------------------------------------------------------------------------
// useSendMessage — offline queue (GraphQL mutation error)
// ---------------------------------------------------------------------------

describe('useSendMessage — offline queue', () => {
  it('retries on GraphQL mutation NetworkError', async () => {
    mockMutate
      .mockResolvedValueOnce({
        data: null,
        error: { message: '[Network] fetch failed' },
      })
      .mockResolvedValue(OK_MUTATION_RESULT);

    const opts = makeOptions();
    const { result } = renderHook(() => useSendMessage(opts));

    const sendPromise = act(async () => {
      await result.current.sendMessage('offline test');
    });

    // Advance timer for first retry backoff (1 s)
    await act(async () => {
      jest.advanceTimersByTime(1000);
    });

    await sendPromise;

    // chatSend called twice: first attempt + first retry
    expect(mockChatSend).toHaveBeenCalledTimes(2);
    expect(result.current.status).toBe('sent');
  });
});
