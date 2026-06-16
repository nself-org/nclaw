/**
 * Unit tests — useAmbientContext hook.
 *
 * Purpose: Verify that useAmbientContext:
 *   1. Returns null context block when disabled.
 *   2. Starts sensor subscriptions when enabled.
 *   3. Exposes motion/location/battery state from mocked sensor readings.
 *   4. Returns a valid context block once motion and battery are available.
 *   5. Returns null location when location is not available (simulates denial).
 *   6. Stops subscriptions when unmounted.
 *
 * Inputs:  Mocked react-native-sensors, expo-location, expo-battery.
 * Outputs: Assertions on getContextBlock(), state fields, subscription lifecycle.
 *
 * Constraints: Uses renderHook + act from @testing-library/react-native.
 *              All sensor modules are mocked at module level.
 */

import { renderHook, act } from '@testing-library/react-native';
import { useAmbientContext } from '../hooks/useAmbientContext';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

// Capture the callbacks the service registers so tests can trigger readings.
let capturedOnMotion: ((r: { x: number; y: number; z: number }) => void) | undefined;
let capturedOnLocation: ((r: { lat: number; lng: number; accuracy: number } | null) => void) | undefined;
let capturedOnBattery: ((r: { level: number; charging: boolean }) => void) | undefined;

const mockStart = jest.fn();
const mockStop = jest.fn();

jest.mock('../services/ambientSensorService', () => ({
  createAmbientSensorSubscription: (callbacks: {
    onMotion?: (r: unknown) => void;
    onLocation?: (r: unknown) => void;
    onBattery?: (r: unknown) => void;
  }) => {
    capturedOnMotion = callbacks.onMotion as typeof capturedOnMotion;
    capturedOnLocation = callbacks.onLocation as typeof capturedOnLocation;
    capturedOnBattery = callbacks.onBattery as typeof capturedOnBattery;
    return { start: mockStart, stop: mockStop };
  },
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function reset(): void {
  capturedOnMotion = undefined;
  capturedOnLocation = undefined;
  capturedOnBattery = undefined;
  mockStart.mockClear();
  mockStop.mockClear();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('useAmbientContext', () => {
  beforeEach(reset);

  it('returns null context block when disabled', () => {
    const { result } = renderHook(() => useAmbientContext(false));
    expect(result.current.motion).toBeNull();
    expect(result.current.location).toBeNull();
    expect(result.current.battery).toBeNull();
    expect(result.current.getContextBlock()).toBeNull();
  });

  it('does not start sensors when disabled', () => {
    renderHook(() => useAmbientContext(false));
    expect(mockStart).not.toHaveBeenCalled();
  });

  it('starts sensors when enabled', () => {
    renderHook(() => useAmbientContext(true));
    expect(mockStart).toHaveBeenCalledTimes(1);
  });

  it('stops sensors on unmount', () => {
    const { unmount } = renderHook(() => useAmbientContext(true));
    unmount();
    expect(mockStop).toHaveBeenCalledTimes(1);
  });

  it('updates motion state from sensor callback', () => {
    const { result } = renderHook(() => useAmbientContext(true));
    act(() => {
      capturedOnMotion?.({ x: 0.1, y: -0.2, z: 9.8 });
    });
    expect(result.current.motion).toEqual({ x: 0.1, y: -0.2, z: 9.8 });
  });

  it('updates location state from sensor callback', () => {
    const { result } = renderHook(() => useAmbientContext(true));
    act(() => {
      capturedOnLocation?.({ lat: 51.5, lng: -0.1, accuracy: 15 });
    });
    expect(result.current.location).toEqual({ lat: 51.5, lng: -0.1, accuracy: 15 });
  });

  it('sets location to null when permission denied (callback receives null)', () => {
    const { result } = renderHook(() => useAmbientContext(true));
    act(() => {
      capturedOnLocation?.(null);
    });
    expect(result.current.location).toBeNull();
  });

  it('updates battery state from sensor callback', () => {
    const { result } = renderHook(() => useAmbientContext(true));
    act(() => {
      capturedOnBattery?.({ level: 0.72, charging: false });
    });
    expect(result.current.battery).toEqual({ level: 0.72, charging: false });
  });

  it('returns null context block until both motion and battery are available', () => {
    const { result } = renderHook(() => useAmbientContext(true));

    // Only motion available — no battery yet.
    act(() => {
      capturedOnMotion?.({ x: 0.0, y: 0.0, z: 9.8 });
    });
    expect(result.current.getContextBlock()).toBeNull();

    // Now battery available.
    act(() => {
      capturedOnBattery?.({ level: 0.5, charging: true });
    });
    expect(result.current.getContextBlock()).not.toBeNull();
  });

  it('returns full context block with all fields when sensors are active', () => {
    const { result } = renderHook(() => useAmbientContext(true));
    act(() => {
      capturedOnMotion?.({ x: 0.1, y: 0.2, z: 9.8 });
      capturedOnLocation?.({ lat: 48.8, lng: 2.3, accuracy: 10 });
      capturedOnBattery?.({ level: 0.9, charging: false });
    });

    const block = result.current.getContextBlock();
    expect(block).not.toBeNull();
    expect(block?.motion).toEqual({ x: 0.1, y: 0.2, z: 9.8 });
    expect(block?.location).toEqual({ lat: 48.8, lng: 2.3, accuracy: 10 });
    expect(block?.battery).toEqual({ level: 0.9, charging: false });
  });

  it('returns context block with null location when location was denied', () => {
    const { result } = renderHook(() => useAmbientContext(true));
    act(() => {
      capturedOnMotion?.({ x: 0.0, y: 0.0, z: 9.8 });
      capturedOnLocation?.(null);
      capturedOnBattery?.({ level: 0.4, charging: true });
    });

    const block = result.current.getContextBlock();
    expect(block).not.toBeNull();
    expect(block?.location).toBeNull();
  });

  it('getContextBlock returns null when disabled even after sensor readings', () => {
    // Start enabled, get readings, then switch to disabled.
    const { result, rerender } = renderHook(
      ({ enabled }: { enabled: boolean }) => useAmbientContext(enabled),
      { initialProps: { enabled: true } },
    );

    act(() => {
      capturedOnMotion?.({ x: 0.0, y: 0.0, z: 9.8 });
      capturedOnBattery?.({ level: 0.8, charging: false });
    });

    rerender({ enabled: false });
    expect(result.current.getContextBlock()).toBeNull();
  });
});
