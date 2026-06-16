/**
 * useAmbientContext — subscribe to ambient sensors and expose context for AI prompts.
 *
 * Purpose: Wraps ambientSensorService to provide real-world device context
 *          (motion, GPS location, battery level) that useSendMessage injects into
 *          every inference prompt. Mirrors the Flutter ambient_sensor_service.dart
 *          context schema so the AI prompt format is identical across platforms.
 *
 * Inputs:  enabled — when false, all sensor subscriptions are inactive and
 *                    getContextBlock() returns null.
 * Outputs: { motion, location, battery, getContextBlock }
 *
 * Constraints:
 *   - Accelerometer at 1 Hz (1000 ms); location polled every 5 minutes;
 *     battery is event-driven. No 60 Hz reads.
 *   - Location denied → location field is null, not an error.
 *   - getContextBlock() returns null when disabled or when no readings exist yet.
 *   - Context format matches Flutter service JSON schema:
 *     { motion: {x,y,z}, location: {lat,lng,accuracy}|null, battery: {level, charging} }
 *   - Composable hook — never placed directly in JSX tree; used by useSendMessage.
 *   - Permissions are NOT requested here — callers (AmbientSettingsToggle) must
 *     request permissions before enabling.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: ambientSensorService.ts · useSendMessage.ts · AmbientSettingsToggle.tsx
 *            T-P3-E4-W2-S3-T10
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import {
  createAmbientSensorSubscription,
  type BatteryReading,
  type LocationReading,
  type MotionReading,
} from '../services/ambientSensorService';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Context block schema — mirrors Flutter ambient_sensor_service.dart. */
export interface AmbientContextBlock {
  motion: MotionReading;
  location: LocationReading | null;
  battery: BatteryReading;
}

export interface UseAmbientContextResult {
  /** Latest accelerometer reading; null until first update. */
  motion: MotionReading | null;
  /** Latest location; null when denied or not yet polled. */
  location: LocationReading | null;
  /** Latest battery reading; null until first update. */
  battery: BatteryReading | null;
  /**
   * Return a formatted context block for AI prompt injection, or null when
   * disabled or when motion/battery haven't been read yet.
   */
  getContextBlock: () => AmbientContextBlock | null;
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export function useAmbientContext(enabled: boolean): UseAmbientContextResult {
  const [motion, setMotion] = useState<MotionReading | null>(null);
  const [location, setLocation] = useState<LocationReading | null>(null);
  const [battery, setBattery] = useState<BatteryReading | null>(null);

  // Keep latest values in refs so getContextBlock callback is stable.
  const motionRef = useRef<MotionReading | null>(null);
  const locationRef = useRef<LocationReading | null>(null);
  const batteryRef = useRef<BatteryReading | null>(null);
  const enabledRef = useRef(enabled);

  // Sync refs on each render so the stable callback always reads current values.
  motionRef.current = motion;
  locationRef.current = location;
  batteryRef.current = battery;
  enabledRef.current = enabled;

  useEffect(() => {
    if (!enabled) return;

    const subscription = createAmbientSensorSubscription({
      onMotion: (reading) => {
        setMotion(reading);
      },
      onLocation: (reading) => {
        setLocation(reading);
      },
      onBattery: (reading) => {
        setBattery(reading);
      },
    });

    subscription.start();
    return () => {
      subscription.stop();
    };
  }, [enabled]);

  const getContextBlock = useCallback((): AmbientContextBlock | null => {
    if (!enabledRef.current) return null;
    const m = motionRef.current;
    const b = batteryRef.current;
    // Require at least motion + battery before injecting context.
    if (!m || !b) return null;
    return {
      motion: m,
      location: locationRef.current,
      battery: b,
    };
  }, []);

  return { motion, location, battery, getContextBlock };
}
