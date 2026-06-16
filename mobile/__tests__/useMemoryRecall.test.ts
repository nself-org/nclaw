/**
 * Unit tests — useMemoryRecall hook.
 *
 * Purpose: Verify that useMemoryRecall correctly calls getNcLawJSI().memorySearch(),
 *          formats the result as a memory context block, tracks isRecalling state,
 *          and handles errors gracefully without rethrowing.
 *
 * Inputs:  Mocked @nself/native-bridge getNcLawJSI().memorySearch.
 * Outputs: Assertions on recall string format, isRecalling lifecycle, error capture.
 *
 * Constraints: Uses renderHook + act from @testing-library/react-native.
 *              @nself/native-bridge is mocked at module level.
 */

import { renderHook, act } from '@testing-library/react-native';
import { useMemoryRecall } from '../hooks/useMemoryRecall';
import type { Memory } from '@nself/native-bridge';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const mockMemorySearch = jest.fn<Promise<Memory[]>, [string, number]>();

jest.mock('@nself/native-bridge', () => ({
  getNcLawJSI: () => ({
    memorySearch: mockMemorySearch,
  }),
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeMemory(overrides: Partial<Memory> = {}): Memory {
  return {
    id: 'mem-1',
    userId: 'user-1',
    topicId: null,
    content: 'User prefers TypeScript.',
    memoryType: 'preference',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    confidence: 0.95,
    sources: [],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  mockMemorySearch.mockReset();
});

describe('useMemoryRecall', () => {
  it('returns null recall initially (no query run)', () => {
    const { result } = renderHook(() => useMemoryRecall());
    expect(result.current.recall).toBeNull();
    expect(result.current.isRecalling).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('sets isRecalling to true while memorySearch is pending', async () => {
    let resolveSearch!: (v: Memory[]) => void;
    mockMemorySearch.mockReturnValue(new Promise((res) => { resolveSearch = res; }));

    const { result } = renderHook(() => useMemoryRecall());

    let recallPromise: Promise<string | null>;
    act(() => {
      recallPromise = result.current.recallForQuery('TypeScript');
    });

    // isRecalling should be true while promise is pending
    expect(result.current.isRecalling).toBe(true);

    await act(async () => {
      resolveSearch([makeMemory()]);
      await recallPromise!;
    });

    expect(result.current.isRecalling).toBe(false);
  });

  it('formats a single memory into a context block', async () => {
    const memory = makeMemory({ content: 'User prefers TypeScript.', memoryType: 'preference' });
    mockMemorySearch.mockResolvedValue([memory]);

    const { result } = renderHook(() => useMemoryRecall());

    let ctx: string | null = undefined!;
    await act(async () => {
      ctx = await result.current.recallForQuery('programming language');
    });

    expect(ctx).not.toBeNull();
    expect(ctx).toContain('<memory_context>');
    expect(ctx).toContain('User prefers TypeScript.');
    expect(ctx).toContain('preference');
    expect(ctx).toContain('</memory_context>');
    expect(result.current.recall).toBe(ctx);
  });

  it('formats multiple memories with numbered indices', async () => {
    const memories = [
      makeMemory({ id: 'mem-1', content: 'Fact A', memoryType: 'fact' }),
      makeMemory({ id: 'mem-2', content: 'Fact B', memoryType: 'goal' }),
    ];
    mockMemorySearch.mockResolvedValue(memories);

    const { result } = renderHook(() => useMemoryRecall());

    let ctx: string | null;
    await act(async () => {
      ctx = await result.current.recallForQuery('query');
    });

    expect(ctx).toContain('[1]');
    expect(ctx).toContain('[2]');
    expect(ctx).toContain('Fact A');
    expect(ctx).toContain('Fact B');
  });

  it('returns null and sets error when memorySearch throws', async () => {
    mockMemorySearch.mockRejectedValue(new Error('JSI not connected'));

    const { result } = renderHook(() => useMemoryRecall());

    let ctx: string | null;
    await act(async () => {
      ctx = await result.current.recallForQuery('query');
    });

    expect(ctx).toBeNull();
    expect(result.current.recall).toBeNull();
    expect(result.current.error).not.toBeNull();
    expect(result.current.error?.message).toBe('JSI not connected');
    expect(result.current.isRecalling).toBe(false);
  });

  it('returns null when memorySearch returns empty array', async () => {
    mockMemorySearch.mockResolvedValue([]);

    const { result } = renderHook(() => useMemoryRecall());

    let ctx: string | null;
    await act(async () => {
      ctx = await result.current.recallForQuery('no match');
    });

    expect(ctx).toBeNull();
    expect(result.current.recall).toBeNull();
    expect(result.current.error).toBeNull();
  });

  it('calls memorySearch with limit of 5', async () => {
    mockMemorySearch.mockResolvedValue([]);

    const { result } = renderHook(() => useMemoryRecall());

    await act(async () => {
      await result.current.recallForQuery('test');
    });

    expect(mockMemorySearch).toHaveBeenCalledWith('test', 5);
  });
});
