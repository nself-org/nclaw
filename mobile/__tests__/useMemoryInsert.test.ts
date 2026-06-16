/**
 * Unit tests — useMemoryInsert hook.
 *
 * Purpose: Verify that useMemoryInsert fires memoryInsert non-blocking, tracks
 *          isInserting state, and captures errors without rethrowing.
 *
 * Inputs:  Mocked @nself/native-bridge getNcLawJSI().memoryInsert.
 * Outputs: Assertions on fire-and-forget behaviour, isInserting lifecycle, error capture.
 *
 * Constraints: insertMemory() must return void (not a promise).
 *              Uses renderHook + act from @testing-library/react-native.
 */

import { renderHook, act } from '@testing-library/react-native';
import { useMemoryInsert } from '../hooks/useMemoryInsert';
import type { MemoryInsertTurn } from '@nself/native-bridge';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const mockMemoryInsert = jest.fn<Promise<void>, [MemoryInsertTurn]>();

jest.mock('@nself/native-bridge', () => ({
  getNcLawJSI: () => ({
    memoryInsert: mockMemoryInsert,
  }),
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeTurn(overrides: Partial<MemoryInsertTurn> = {}): MemoryInsertTurn {
  return {
    conversationId: 'conv-1',
    role: 'user',
    content: 'Hello',
    model: null,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  mockMemoryInsert.mockReset();
});

describe('useMemoryInsert', () => {
  it('starts with isInserting false and no error', () => {
    const { result } = renderHook(() => useMemoryInsert());
    expect(result.current.isInserting).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('insertMemory returns void (not a promise)', () => {
    mockMemoryInsert.mockResolvedValue(undefined);
    const { result } = renderHook(() => useMemoryInsert());

    const returnValue = result.current.insertMemory(makeTurn());

    // Must be void, not a Promise
    expect(returnValue).toBeUndefined();
  });

  it('calls getNcLawJSI().memoryInsert with the provided turn', async () => {
    mockMemoryInsert.mockResolvedValue(undefined);
    const { result } = renderHook(() => useMemoryInsert());

    const turn = makeTurn({ content: 'Test message', role: 'assistant', model: 'claude-3' });

    await act(async () => {
      result.current.insertMemory(turn);
      // Allow microtask queue to flush
      await Promise.resolve();
    });

    expect(mockMemoryInsert).toHaveBeenCalledWith(turn);
  });

  it('captures error and sets error field without rethrowing', async () => {
    mockMemoryInsert.mockRejectedValue(new Error('DB write failed'));
    const { result } = renderHook(() => useMemoryInsert());

    await act(async () => {
      result.current.insertMemory(makeTurn());
      await new Promise((r) => setTimeout(r, 10));
    });

    expect(result.current.error).not.toBeNull();
    expect(result.current.error?.message).toBe('DB write failed');
    expect(result.current.isInserting).toBe(false);
  });

  it('handles concurrent inserts without serialization constraint', async () => {
    let resolve1!: () => void;
    let resolve2!: () => void;

    mockMemoryInsert
      .mockReturnValueOnce(new Promise<void>((r) => { resolve1 = r; }))
      .mockReturnValueOnce(new Promise<void>((r) => { resolve2 = r; }));

    const { result } = renderHook(() => useMemoryInsert());

    act(() => {
      result.current.insertMemory(makeTurn({ content: 'First' }));
      result.current.insertMemory(makeTurn({ content: 'Second' }));
    });

    // Both inserts in flight
    expect(mockMemoryInsert).toHaveBeenCalledTimes(2);

    await act(async () => {
      resolve1();
      resolve2();
      await Promise.resolve();
    });

    expect(result.current.error).toBeNull();
  });
});
