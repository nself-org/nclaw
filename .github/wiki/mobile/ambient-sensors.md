# Ambient Sensors — ɳClaw Mobile

ɳClaw mobile can optionally inject real-world device context (motion, GPS, battery) into every AI prompt, giving ɳClaw awareness of your physical environment without any manual input.

## What it does

When **Ambient Context** is enabled in Settings, each message you send includes a silent system block:

```json
{
  "motion":   { "x": 0.1, "y": -0.2, "z": 9.8 },
  "location": { "lat": 51.5, "lng": -0.1, "accuracy": 15 },
  "battery":  { "level": 0.72, "charging": false }
}
```

This mirrors the schema from the original Flutter `ambient_sensor_service.dart` so server-side prompt templates work identically across platforms.

## Sensor sources

| Field | Source | Rate |
|---|---|---|
| `motion` | `react-native-sensors` accelerometer | 1 Hz (1000 ms) |
| `location` | `expo-location` foreground GPS | every 5 minutes |
| `battery` | `expo-battery` event listener | on change |

Throttling is intentional to avoid battery drain. No 60 Hz reads.

## Permissions

| Sensor | Permission | Behavior on denial |
|---|---|---|
| Accelerometer | None required (iOS/Android) | Always available |
| Location | `NSLocationWhenInUseUsageDescription` (iOS) / `ACCESS_FINE_LOCATION` (Android) | `location` field → `null` |
| Battery | None required | Always available |

Permissions are requested once when the user first enables Ambient Context via the `AmbientSettingsToggle`. If denied, sensors degrade gracefully — location becomes `null` in the context block.

## Architecture

```
AmbientSettingsToggle        — UI toggle, requests permissions, persists enabled flag
  └─ useSendMessage           — reads enabled flag, calls getContextBlock() per send
       └─ useAmbientContext    — subscribes to sensors, exposes getContextBlock()
            └─ ambientSensorService — manages raw subscriptions (rxjs / expo APIs)
```

- `useAmbientContext` is a composable hook — not placed in JSX. It is called by `useSendMessage`.
- `ambientSensorService` is a pure factory (`createAmbientSensorSubscription`) — stateless, easily unit-tested.
- Context injection point in `useSendMessage`: memory context block first, then ambient block, then user text.

## Settings store key

```
@nclaw/ambient_sensors_enabled
```

Stored in `AsyncStorage`. Default: `false` (off).

## Disabling ambient context

Toggle off in **Settings → Ambient Context**. Sensor subscriptions stop immediately; no data is sent in subsequent prompts.

## Privacy

No location, motion, or battery data is stored in the ɳClaw memory database or transmitted to any server. The context block exists only in the in-flight prompt for that single message.

## Related files

| File | Purpose |
|---|---|
| `mobile/services/ambientSensorService.ts` | Low-level sensor subscriptions |
| `mobile/hooks/useAmbientContext.ts` | React hook exposing sensor state + context block |
| `mobile/hooks/useSendMessage.ts` | Context injection point |
| `mobile/components/AmbientSettingsToggle.tsx` | Settings UI |
| `mobile/__tests__/useAmbientContext.test.ts` | Unit tests (mocked sensors) |

## Testing

Unit tests run with mocked sensor modules — no device required:

```bash
pnpm --dir nclaw/mobile test useAmbientContext
```

For E2E verification on a real device:

1. Enable Ambient Context in Settings.
2. Send a message.
3. In a dev build, check the JS console for the `[system:ambient]` block in the logged prompt.
