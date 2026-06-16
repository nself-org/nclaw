# ɳClaw Mobile Home Screen Widget

Home screen widget implementation for iOS WidgetKit and Android App Widgets.

## Overview

The home screen widget displays:
1. Last AI conversation summary (or auto-generated preview)
2. Quick-capture button to open the app and jump to quick capture screen

Data is shared between the app and widget via:
- **iOS**: UserDefaults app group (`group.org.nself.nclaw.widget`)
- **Android**: SharedPreferences (`org.nself.nclaw.widget`)

## File Structure

```
widget/
├── ios/
│   ├── NClawWidget.swift          # iOS WidgetKit extension (SwiftUI)
│   └── README.md
├── android/
│   ├── NClawWidget.xml            # Android widget layout (RemoteViews)
│   ├── NClawWidgetProvider.kt     # Android widget provider + receiver
│   ├── AndroidManifest.snippet.xml # Manifest declarations
│   ├── nclaw_appwidget_provider.xml # Widget metadata
│   ├── widget_background.xml      # Background gradient drawable
│   ├── widget_button_background.xml # Button style drawable
│   └── README.md
├── README.md                      # This file
```

## Services

### `services/homeWidgetService.ts`

TypeScript service for managing widget data from the React Native app:

```typescript
import { updateWidgetData, readWidgetData, clearWidgetData } from '~/services/homeWidgetService';

// After conversation completes, update widget
await updateWidgetData('Last chat: How does AI work?', 'nclaw://capture');

// Read widget data (for debugging)
const data = await readWidgetData();

// Clear widget data (on logout)
await clearWidgetData();
```

**Constraints:**
- Native bridge (iOS UserDefaults / Android SharedPreferences) is stubbed; integration required.
- Call `updateWidgetData()` after each message completion, not on every keystroke.
- Summary should be <80 chars for optimal widget display.

## iOS Setup

### Requirements
- iOS 14+ (WidgetKit requirement)
- Xcode project with app group entitlement

### Configuration
1. In `app.json`, `ios.appGroups` includes `group.org.nself.nclaw.widget`.
2. Expo's build system auto-configures the app group entitlement in the signed app.
3. WidgetKit extension is built as a separate target; managed via Expo's `expo-build-properties`.

### Testing
```bash
# Build for iOS
cd nclaw/mobile && eas build --platform ios --profile production

# On physical device or simulator:
# 1. Long-press home screen → Add widget → ɳClaw Summary
# 2. Widget displays last summary; tap "Quick Capture" to open app
```

## Android Setup

### Requirements
- Android API 16+ (App Widget requirement)
- SharedPreferences read/write permissions (automatic)

### Configuration
1. In `app.json`, no explicit configuration needed; Expo handles the build.
2. Native bridge writes widget data to SharedPreferences with key `org.nself.nclaw.widget`.
3. Widget provider (`NClawWidgetProvider.kt`) reads and updates widget UI every 30 min or on manual refresh.

### Manifest Integration
The `AndroidManifest.snippet.xml` must be merged into the main `AndroidManifest.xml`:
- Declares widget receiver and provider metadata
- Registers quick-capture broadcast action

For Expo managed builds, use `expo-build-properties` to inject custom manifest entries if needed.

### Testing
```bash
# Build for Android
cd nclaw/mobile && eas build --platform android --profile production

# On physical device or emulator:
# 1. Long-press home screen → Widgets → ɳClaw
# 2. Widget displays last summary; tap "Quick Capture" to open app
```

## Deep Linking

Widget tap → `nclaw://capture` deep link → handled in `app/(tabs)/chat.tsx` (T04 deep link router).

The app's Expo Router is configured with scheme `nclaw` in `app.json`. Deep link handler:
```typescript
// In app/(tabs)/chat.tsx or app/index.tsx
useEffect(() => {
  const subscription = linking.addEventListener('url', ({ url }) => {
    if (url.includes('capture')) {
      // Navigate to quick capture screen
    }
  });
  return () => subscription.remove();
}, []);
```

## Native Bridge Implementation (TODO)

The `homeWidgetService.ts` includes stub functions for native bridge calls:
- `writeToIOSUserDefaults(data)` — needs wiring to RN module or native iOS code
- `writeToAndroidSharedPreferences(data)` — needs wiring to RN module or native Android code

Options:
1. **react-native-shared-preferences** (if available for app groups on iOS)
2. **Custom RN native module** (NativeModules call to Swift/Kotlin)
3. **Expo Modules API** (newer Expo version)

For MVP, the stubs log intent; widget will read empty/cached data until bridge is wired.

## Data Format

Widget data stored in JSON format:
```json
{
  "lastSummary": "Last chat: How does machine learning work?",
  "captureDeepLink": "nclaw://capture",
  "updatedAt": 1686789012345
}
```

- **lastSummary**: User-facing text, max 80 chars recommended
- **captureDeepLink**: Deep link URL (default: `nclaw://capture`)
- **updatedAt**: Unix timestamp (milliseconds)

## Testing Checklist (QA-A)

- [ ] iOS: Add widget to home screen; verify last summary displays
- [ ] iOS: Widget tap → opens app to quick capture screen
- [ ] iOS: Complete a conversation; verify widget updates without reopening app
- [ ] Android: Add widget to home screen; verify last summary displays
- [ ] Android: Widget tap → opens app to quick capture screen
- [ ] Android: Complete a conversation; verify widget updates without reopening app
- [ ] EAS production build includes widget extension (no build errors)
- [ ] Deep link `nclaw://capture` opens quick capture screen

## References

- T-P3-E4-W2-S3-T04: Deep link handler
- T-P3-E4-W2-S3-T12: This ticket
- F08-SERVICE-INVENTORY.md: Service inventory (SPORT)
