/**
 * Unit tests — useAutoTopics hook.
 *
 * Purpose: Verify that useAutoTopics subscribes to topic_auto_classify, merges
 *          incoming Topic rows into a deduped sorted list, skips subscription
 *          when userId is undefined, and surfaces errors correctly.
 *
 * Inputs:  Mocked @apollo/client useSubscription.
 * Outputs: Assertions on topic merge, deduplication, sort order, skip behaviour.
 *
 * Constraints: Uses renderHook + act from @testing-library/react-native.
 *              @apollo/client is mocked at module level.
 */

import { renderHook, act } from '@testing-library/react-native';
import { useAutoTopics } from '../hooks/useAutoTopics';
import type { Topic } from '@nself/native-bridge';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

type SubscriptionResult<T> = {
  data: T | undefined;
  loading: boolean;
  error: Error | undefined;
};

const mockUseSubscription = jest.fn<
  SubscriptionResult<{ topic_auto_classify: Partial<Topic>[] }>,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  any[]
>();

jest.mock('@apollo/client', () => ({
  useSubscription: (...args: unknown[]) => mockUseSubscription(...args),
  gql: (strings: TemplateStringsArray) => strings.join(''),
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeTopicRow(overrides: Partial<Topic> = {}): Topic {
  return {
    id: 'topic-1',
    userId: 'user-1',
    title: 'TypeScript',
    description: null,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    entityCount: 3,
    conversationCount: 1,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  mockUseSubscription.mockReset();
});

describe('useAutoTopics', () => {
  it('returns empty topics initially with no subscription data', () => {
    mockUseSubscription.mockReturnValue({ data: undefined, loading: false, error: undefined });

    const { result } = renderHook(() => useAutoTopics('user-1'));

    expect(result.current.topics).toEqual([]);
    expect(result.current.loading).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('reflects loading: true when subscription is establishing', () => {
    mockUseSubscription.mockReturnValue({ data: undefined, loading: true, error: undefined });

    const { result } = renderHook(() => useAutoTopics('user-1'));

    expect(result.current.loading).toBe(true);
  });

  it('populates topics from subscription data', () => {
    const topic = makeTopicRow({ id: 'topic-1', title: 'TypeScript' });
    mockUseSubscription.mockReturnValue({
      data: { topic_auto_classify: [topic] },
      loading: false,
      error: undefined,
    });

    const { result } = renderHook(() => useAutoTopics('user-1'));

    expect(result.current.topics).toHaveLength(1);
    expect(result.current.topics[0]?.id).toBe('topic-1');
    expect(result.current.topics[0]?.title).toBe('TypeScript');
  });

  it('deduplicates topics by id on repeated subscription events', () => {
    const topic = makeTopicRow({ id: 'topic-1', title: 'TypeScript', entityCount: 3 });
    mockUseSubscription.mockReturnValue({
      data: { topic_auto_classify: [topic] },
      loading: false,
      error: undefined,
    });

    const { result, rerender } = renderHook(() => useAutoTopics('user-1'));
    expect(result.current.topics).toHaveLength(1);

    // Same id, updated entityCount — should update rather than append
    const updatedTopic = makeTopicRow({ id: 'topic-1', title: 'TypeScript', entityCount: 5 });
    mockUseSubscription.mockReturnValue({
      data: { topic_auto_classify: [updatedTopic] },
      loading: false,
      error: undefined,
    });

    act(() => { rerender({}); });

    expect(result.current.topics).toHaveLength(1);
    expect(result.current.topics[0]?.entityCount).toBe(5);
  });

  it('sorts topics newest-first by updatedAt', () => {
    const older = makeTopicRow({ id: 't1', title: 'Old', updatedAt: '2026-01-01T00:00:00Z' });
    const newer = makeTopicRow({ id: 't2', title: 'New', updatedAt: '2026-06-01T00:00:00Z' });
    mockUseSubscription.mockReturnValue({
      data: { topic_auto_classify: [older, newer] },
      loading: false,
      error: undefined,
    });

    const { result } = renderHook(() => useAutoTopics('user-1'));

    expect(result.current.topics[0]?.id).toBe('t2'); // newer first
    expect(result.current.topics[1]?.id).toBe('t1');
  });

  it('skips subscription when userId is undefined', () => {
    mockUseSubscription.mockReturnValue({ data: undefined, loading: false, error: undefined });

    renderHook(() => useAutoTopics(undefined));

    // The skip: true option should have been passed to useSubscription
    const callArgs = mockUseSubscription.mock.calls[0];
    expect(callArgs?.[1]).toMatchObject({ skip: true });
  });

  it('surfaces GraphQL errors via the error field', () => {
    const gqlError = new Error('Subscription closed');
    mockUseSubscription.mockReturnValue({ data: undefined, loading: false, error: gqlError });

    const { result } = renderHook(() => useAutoTopics('user-1'));

    expect(result.current.error).toBe(gqlError);
    expect(result.current.topics).toEqual([]);
  });
});
