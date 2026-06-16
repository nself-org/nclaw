/**
 * Tests for hooks/useNetworkStatus.ts
 *
 * Coverage:
 *   - Returns isOnline=true by default (navigator.onLine = true)
 *   - Returns isOnline=false when navigator.onLine = false on mount
 *   - Updates isOnline=false when 'offline' window event fires
 *   - Updates isOnline=true when 'online' window event fires
 *   - SSR-safe: no crash when navigator is undefined
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useNetworkStatus } from '../useNetworkStatus';

describe('useNetworkStatus', () => {
  const originalOnLine = Object.getOwnPropertyDescriptor(window.navigator, 'onLine');

  function setOnLine(value: boolean) {
    Object.defineProperty(window.navigator, 'onLine', {
      configurable: true,
      writable: true,
      value,
    });
  }

  beforeEach(() => {
    setOnLine(true);
  });

  afterEach(() => {
    if (originalOnLine) {
      Object.defineProperty(window.navigator, 'onLine', originalOnLine);
    }
  });

  it('returns isOnline=true when navigator.onLine is true', () => {
    setOnLine(true);
    const { result } = renderHook(() => useNetworkStatus());
    expect(result.current.isOnline).toBe(true);
  });

  it('returns isOnline=false when navigator.onLine is false on mount', () => {
    setOnLine(false);
    const { result } = renderHook(() => useNetworkStatus());
    expect(result.current.isOnline).toBe(false);
  });

  it('updates isOnline=false when offline event fires', () => {
    setOnLine(true);
    const { result } = renderHook(() => useNetworkStatus());
    expect(result.current.isOnline).toBe(true);

    act(() => {
      setOnLine(false);
      window.dispatchEvent(new Event('offline'));
    });

    expect(result.current.isOnline).toBe(false);
  });

  it('updates isOnline=true when online event fires', () => {
    setOnLine(false);
    const { result } = renderHook(() => useNetworkStatus());
    expect(result.current.isOnline).toBe(false);

    act(() => {
      setOnLine(true);
      window.dispatchEvent(new Event('online'));
    });

    expect(result.current.isOnline).toBe(true);
  });

  it('removes event listeners on unmount (no memory leak)', () => {
    const addSpy = vi.spyOn(window, 'addEventListener');
    const removeSpy = vi.spyOn(window, 'removeEventListener');

    const { unmount } = renderHook(() => useNetworkStatus());
    unmount();

    const onlineAdd = addSpy.mock.calls.filter(([ev]) => ev === 'online').length;
    const offlineAdd = addSpy.mock.calls.filter(([ev]) => ev === 'offline').length;
    const onlineRemove = removeSpy.mock.calls.filter(([ev]) => ev === 'online').length;
    const offlineRemove = removeSpy.mock.calls.filter(([ev]) => ev === 'offline').length;

    expect(onlineAdd).toBeGreaterThan(0);
    expect(offlineAdd).toBeGreaterThan(0);
    expect(onlineRemove).toBe(onlineAdd);
    expect(offlineRemove).toBe(offlineAdd);

    addSpy.mockRestore();
    removeSpy.mockRestore();
  });
});
