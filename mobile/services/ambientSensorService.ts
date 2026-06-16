/**
 * ambientSensorService — low-level ambient sensor subscriptions for nclaw/mobile.
 *
 * Purpose: Manages react-native-sensors accelerometer, expo-location polling, and
 *          expo-battery change events. Exposes a single subscribe() + unsubscribe()
 *          lifecycle so useAmbientContext can start/stop all sensors atomically.
 *
 * Inputs:  AmbientSensorCallbacks — optional callbacks for each sensor type.
 * Outputs: AmbientSensorSubscription — { start(), stop() }
 *
 * Constraints:
 *   - Accelerometer rate: 1 Hz (1000 ms interval) — never higher (battery drain).
 *   - Location poll: 5-minute interval, low accuracy (balanced power mode).
 *   - Battery: event-driven (on change), no polling.
 *   - Permission denial → null data, no throw.
 *   - Each sensor wraps its own try/catch; one failed sensor does NOT block others.
 *   - Stateless module — caller holds the subscription handle and calls stop().
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: useAmbientContext.ts · T-P3-E4-W2-S3-T10
 */

import {
  accelerometer,
  setUpdateIntervalForType,
  SensorTypes,
} from 'react-native-sensors';
import * as Location from 'expo-location';
import * as Battery from 'expo-battery';
import { Subscription } from 'rxjs';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface MotionReading {
  x: number;
  y: number;
  z: number;
}

export interface LocationReading {
  lat: number;
  lng: number;
  accuracy: number;
}

export interface BatteryReading {
  level: number;
  /** True when charging or fully charged. */
  charging: boolean;
}

export interface AmbientSensorCallbacks {
  onMotion?: (motion: MotionReading) => void;
  onLocation?: (location: LocationReading | null) => void;
  onBattery?: (battery: BatteryReading) => void;
}

export interface AmbientSensorSubscription {
  /** Start all sensor subscriptions. */
  start(): void;
  /** Stop all sensor subscriptions and release resources. */
  stop(): void;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Accelerometer update interval in milliseconds. 1 Hz. */
const ACCEL_INTERVAL_MS = 1000;

/** Location poll interval in milliseconds. 5 minutes. */
const LOCATION_INTERVAL_MS = 5 * 60 * 1000;

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/**
 * Create an ambient sensor subscription handle.
 * Call start() to activate; call stop() when done.
 */
export function createAmbientSensorSubscription(
  callbacks: AmbientSensorCallbacks,
): AmbientSensorSubscription {
  let accelSub: Subscription | null = null;
  let locationInterval: ReturnType<typeof setInterval> | null = null;
  let batteryUnsubscribe: Battery.Subscription | null = null;
  let running = false;

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  async function pollLocation(): Promise<void> {
    if (!callbacks.onLocation) return;
    try {
      const { status } = await Location.getForegroundPermissionsAsync();
      if (status !== 'granted') {
        callbacks.onLocation(null);
        return;
      }
      const pos = await Location.getCurrentPositionAsync({
        accuracy: Location.Accuracy.Balanced,
      });
      callbacks.onLocation({
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        accuracy: pos.coords.accuracy ?? 0,
      });
    } catch {
      // Permission revoked mid-session or location unavailable.
      callbacks.onLocation(null);
    }
  }

  function startAccelerometer(): void {
    if (!callbacks.onMotion) return;
    try {
      setUpdateIntervalForType(SensorTypes.accelerometer, ACCEL_INTERVAL_MS);
      accelSub = accelerometer.subscribe({
        next: ({ x, y, z }) => {
          callbacks.onMotion?.({ x, y, z });
        },
        error: () => {
          // Sensor unavailable — suppress and continue.
        },
      });
    } catch {
      // react-native-sensors not linked or sensor absent — no-op.
    }
  }

  function startLocation(): void {
    if (!callbacks.onLocation) return;
    // Initial poll immediately.
    void pollLocation();
    locationInterval = setInterval(() => {
      void pollLocation();
    }, LOCATION_INTERVAL_MS);
  }

  async function startBattery(): Promise<void> {
    if (!callbacks.onBattery) return;
    try {
      // Initial read.
      const level = await Battery.getBatteryLevelAsync();
      const state = await Battery.getBatteryStateAsync();
      callbacks.onBattery({
        level: Math.max(0, Math.min(1, level)),
        charging:
          state === Battery.BatteryState.CHARGING ||
          state === Battery.BatteryState.FULL,
      });
      // Subscribe to future changes.
      batteryUnsubscribe = Battery.addBatteryStateListener(({ batteryState }) => {
        void Battery.getBatteryLevelAsync().then((lvl) => {
          callbacks.onBattery?.({
            level: Math.max(0, Math.min(1, lvl)),
            charging:
              batteryState === Battery.BatteryState.CHARGING ||
              batteryState === Battery.BatteryState.FULL,
          });
        });
      });
    } catch {
      // Battery API unavailable (simulator / TV) — no-op.
    }
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  return {
    start() {
      if (running) return;
      running = true;
      startAccelerometer();
      startLocation();
      void startBattery();
    },

    stop() {
      if (!running) return;
      running = false;

      if (accelSub) {
        accelSub.unsubscribe();
        accelSub = null;
      }
      if (locationInterval !== null) {
        clearInterval(locationInterval);
        locationInterval = null;
      }
      if (batteryUnsubscribe) {
        batteryUnsubscribe.remove();
        batteryUnsubscribe = null;
      }
    },
  };
}
