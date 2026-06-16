# ɳClaw Mobile — Biometric App Lock (Face ID / Fingerprint)

## Overview

The biometric app lock feature protects ɳClaw mobile by requiring Face ID or fingerprint authentication when the app is opened or resumed from the background. This safeguards user conversations and AI memory from unauthorized access.

**Status:** Implemented in P3 E4 W2 S3 (T-P3-E4-W2-S3-T15)
**Version:** 1.1.1+

---

## Architecture

### Stack

- **Provider:** `expo-local-authentication` (via `@nself/native-bridge`)
- **State Management:** `useBiometricAuth` hook + `BiometricLockService`
- **UI:** `BiometricLockScreen` overlay component + biometric settings screen
- **Storage:** `expo-secure-store` (encrypted preference persist)

### Component Hierarchy

```
RootLayout (+layout.tsx)
  ├─ useBiometricAuth() — preference + enrollment + AppState listener
  └─ BiometricLockScreen — overlay gate when locked
      └─ onAuthenticate() → biometricLockService.authenticate()

SettingsScreen
  └─ /settings/biometric-settings
      └─ BiometricSettingsScreen — enable/disable toggle
          └─ biometricLockService.loadPreference() / savePreference()
```

---

## Files

| Path | Purpose |
|------|---------|
| `services/biometricLockService.ts` | Wraps `@nself/native-bridge` biometrics + preference persistence |
| `components/BiometricLockScreen.tsx` | Full-screen lock overlay with ɳ logo + unlock button |
| `hooks/useAppLock.ts` | Modular hook for app lifecycle lock (alternative to useBiometricAuth) |
| `app/+layout.tsx` | Integrates BiometricLockScreen into root navigation |
| `app/settings/biometric-settings.tsx` | Settings sub-screen for toggle + device status |
| `app/settings/_layout.tsx` | Added biometric-settings route |
| `package.json` | Added `expo-local-authentication@~14.0.0` |

---

## How It Works

### 1. Bootstrap (App Start)

1. `RootLayout` mounts and calls `useBiometricAuth()`
2. Hook checks device biometric enrollment via `LocalAuthentication.hasHardwareAsync()` + `isEnrolledAsync()`
3. Hook loads user preference from secure storage (`expo-secure-store`)
4. If preference enabled and device supports biometrics, hook sets `isAuthenticated=false` → lock screen appears
5. `BiometricLockScreen` renders overlay blocking app content

### 2. Unlock Flow

1. User taps **Unlock** button on lock screen
2. `onAuthenticate()` calls `biometricLockService.authenticate()`
3. Service calls `ExpoLocalAuth.authenticate()` → shows OS biometric prompt
4. On Face ID / fingerprint success: `setIsAuthenticated(true)` → lock screen disappears
5. On cancel or failure: lock screen remains; user can retry

### 3. AppState Listener

1. When app transitions from **background → foreground**:
   - `useBiometricAuth()` AppState listener fires
   - If preference enabled: `setIsAuthenticated(false)` → re-locks app
   - Lock screen re-appears
2. User must re-authenticate to resume using app

### 4. Settings (Toggle)

1. Settings screen shows **Biometric Auth** row
2. Navigates to `/settings/biometric-settings`
3. `BiometricSettingsScreen` shows:
   - Device status (enrolled / not enrolled)
   - Enable/disable switch (disabled if no biometrics)
   - Explanation text
4. Toggle saves preference to secure storage via `biometricLockService.savePreference()`

---

## API Reference

### `BiometricLockService`

```typescript
class BiometricLockService {
  async isEnrolled(): Promise<boolean>
  async authenticate(config?: BiometricLockServiceConfig): Promise<boolean>
  async loadPreference(): Promise<boolean>
  async savePreference(enabled: boolean): Promise<void>
}
```

**Usage:**
```typescript
import { biometricLockService } from '../services/biometricLockService';

// Check if device has biometrics
const enrolled = await biometricLockService.isEnrolled();

// Authenticate
const success = await biometricLockService.authenticate({
  promptMessage: 'Unlock ɳClaw',
});

// Load/save preference
const prefEnabled = await biometricLockService.loadPreference();
await biometricLockService.savePreference(true);
```

### `useBiometricAuth()`

```typescript
const { isAuthenticated, isEnrolled, prefEnabled, setPrefEnabled, authenticate }
  = useBiometricAuth();
```

- **isAuthenticated** — Session has passed biometric (or not required)
- **isEnrolled** — Device has enrolled biometrics
- **prefEnabled** — User enabled biometric lock in settings
- **setPrefEnabled(bool)** — Toggle preference + immediately authenticate if enabling
- **authenticate()** — Manually trigger biometric prompt

### `BiometricLockScreen`

```typescript
<BiometricLockScreen
  isLocked={prefEnabled && !isAuthenticated}
  onAuthenticate={authenticate}
  promptMessage="Unlock ɳClaw"
  onCancel={()=> {}}  // optional
/>
```

---

## Acceptance Criteria

✅ **Enable biometric lock in settings → Face ID/fingerprint prompt appears on next foreground**
- Settings toggle saves preference → AppState listener detects foreground → lock screen appears with prompt

✅ **App blocked by lock screen until authentication succeeds**
- `BiometricLockScreen` renders as overlay above Stack; blocks interaction until `onAuthenticate()` returns true

✅ **Background → foreground triggers lock**
- `useBiometricAuth()` AppState listener detects state change and re-locks if preference enabled

✅ **Device without biometrics: toggle disabled with explanation text**
- `BiometricSettingsScreen` checks `isEnrolled` and disables switch; shows explanatory text

✅ **Failed auth → retry button shown, not app crash**
- `BiometricLockScreen` catches errors; shows error message + allows retry; does not crash

---

## Testing

### Physical Device (iOS)

1. Install app: `pnpm ios`
2. Settings → Biometric Auth → Toggle **ON**
3. Return to home; wait 2s
4. Tap ɳClaw app icon
5. Verify Face ID prompt appears
6. **Scenario A:** Authenticate → app unlocks
7. **Scenario B:** Cancel → lock screen remains; tap Unlock → retry
8. **Scenario C:** Minimize (background) → restore (foreground) → lock re-appears

### Physical Device (Android)

1. Install app: `pnpm android`
2. Settings → Biometric Auth → Toggle **ON**
3. Same flow as iOS (fingerprint instead of Face ID)

### Simulator

- Biometric authentication unavailable in simulator (graceful fallback)
- `BiometricSettingsScreen` shows "No Biometric Available"
- Toggle disabled

---

## i18n Keys

The following translation keys are used. Add to your i18n config:

```yaml
biometric:
  status: "Device Status"
  deviceSupported: "Face ID / Fingerprint Available"
  deviceUnsupported: "No Biometric Available"
  deviceUnsupportedExplain: "Your device does not have biometric authentication enrolled. Please enroll Face ID or fingerprint in device settings to use this feature."
  settings: "Lock Settings"
  requireOnOpen: "Require on App Open"
  requireOnOpenHint: "Authenticate every time you open the app"
  requireOnOpenToggle: "Require biometric on app open"
  about: "About"
  aboutText: "When enabled, you will be asked to authenticate with Face ID or fingerprint when you open the app. This protects your conversations and memories from unauthorized access."
  prompt: "Authenticate to continue"
  authFailed: "Authentication failed. Please try again."
  error: "An error occurred. Please try again."
  unlock: "Unlock with biometrics"
  unlockButton: "Unlock"
```

---

## Security Notes

1. **Preference Storage:** Biometric preference is stored in `expo-secure-store` (encrypted on-device)
2. **Prompt Message:** OS-level Face ID / fingerprint UI prevents app from spoofing authentication
3. **Graceful Degradation:** Biometric failures do NOT auto-unlock (user must retry); no hardcoded bypass
4. **No Keychain Integration:** This ticket does NOT cover keychain/vault — that's T-P3-E2-W3-S03-T01

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Toggle shows "No Biometric Available" | Device has no biometrics enrolled. Enroll Face ID / fingerprint in device settings. |
| Lock screen appears but authentication hangs | Rare race condition. Cancel and retry. If persistent, check OS biometric state. |
| Settings pref doesn't persist | Clear app data and re-enable toggle. |
| App crashes on authenticate | Should not occur — errors are caught. File PCI if reproducible. |

---

## Related Tickets

- **T-P3-E2-W3-S03-T01:** Native-bridge SecureStore + keychain vault
- **T-P3-E4-W2-S3-T02:** Settings screen (parent)
- **T-P3-E4-W2-S3-T09:** SPORT updates

---

## References

- **Feature Spec:** `feature-preservation-inventory.md` §1b (biometric_service.dart from Flutter)
- **SPORT:** F08-SERVICE-INVENTORY (nclaw-mobile-biometric-lock)
- **Provider:** `@nself/native-bridge` biometrics seam
