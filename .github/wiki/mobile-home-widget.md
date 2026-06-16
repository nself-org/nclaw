# ɳClaw Mobile Home Screen Widget

## Overview

Home screen widgets provide quick access to ɳClaw without opening the app. Users can view their last conversation summary and trigger quick capture directly from the home screen.

**Platform Support:**
- iOS 14+ (WidgetKit)
- Android 4.1+ (App Widgets)

## User Features

### What the Widget Shows

- **Last AI Summary**: The most recent AI response or auto-generated preview of the last conversation
- **Quick Capture Button**: One-tap access to quickly record an idea or question

### Adding the Widget

**iOS:**
1. Long-press your home screen
2. Tap the + button (bottom left)
3. Search for "ɳClaw" and select "ɳClaw Summary"
4. Tap "Add Widget"

**Android:**
1. Long-press your home screen
2. Tap "Widgets" (or the + button, depending on launcher)
3. Find "ɳClaw" in the list
4. Select "ɳClaw Home Widget" and place on home screen

### Using the Widget

- **View last summary**: The widget displays your most recent conversation
- **Quick capture**: Tap the "Quick Capture" button to open ɳClaw directly to the quick capture screen
- **Auto-refresh**: Widget updates after each conversation without requiring app restart

## Technical Details

### How It Works

1. **Data Sharing**: After each conversation, ɳClaw writes the last summary to shared storage:
   - iOS: UserDefaults app group (`group.org.nself.nclaw.widget`)
   - Android: SharedPreferences

2. **Widget Display**: Widgets read this shared storage and display the summary with a quick-capture button

3. **Deep Linking**: Tapping the widget button opens ɳClaw to the quick capture screen via deep link

### Architecture

```
App                         Shared Storage                  Widget
├─ Complete message ────────────────────────────────────────┐
│                                                             │
├─ Write to UserDefaults/ ──→ [lastSummary, timestamp] ──→ Widget reads
│  SharedPreferences            on refresh interval          and displays
│                                                             │
└─ User taps widget ←───────── Deep link nclaw://capture ────┘
```

### Platforms

| Platform | Technology | Refresh Interval |
|----------|-----------|-----------------|
| iOS | WidgetKit (SwiftUI) | 15 minutes or on app update |
| Android | App Widgets (RemoteViews) | 30 minutes or manual refresh |

## Privacy & Security

- **No data stored on cloud**: Widget data remains on your device
- **App group shared storage**: Only ɳClaw app and widget can access the shared data
- **No background fetch**: Widget only reads data when visible or refreshed
- **No network calls**: Widget operates entirely offline

## Troubleshooting

### Widget Not Updating

- **iOS**: Swipe up from the bottom and ensure ɳClaw is allowed to refresh
- **Android**: Long-press widget and tap "Refresh" or wait for the 30-minute refresh cycle

### Quick Capture Button Not Working

- Ensure ɳClaw app is installed and updated to the latest version
- Reinstall the widget
- Check that deep linking is enabled in app settings

### Widget Missing

- Ensure you're running iOS 14+ or Android 4.1+
- Reinstall ɳClaw app
- Clear app cache and restart device

## Development

For developers building with ɳClaw:

**Files:**
- iOS: `nclaw/mobile/widget/ios/NClawWidget.swift`
- Android: `nclaw/mobile/widget/android/`
- Service: `nclaw/mobile/services/homeWidgetService.ts`

**Integration:**
```typescript
import { updateWidgetData } from '~/services/homeWidgetService';

// After message completion
await updateWidgetData('Last chat: How does AI work?', 'nclaw://capture');
```

See `nclaw/mobile/widget/README.md` for implementation details.
