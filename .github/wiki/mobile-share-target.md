# ɳClaw Mobile Share Target

## Overview

Share target allows users to share content (text, URLs, images) from any iOS or Android app directly into ɳClaw's share composer, enabling quick capture of external content into memory.

**Platforms:** iOS 13+ · Android 5+

## iOS Implementation

### Share Extension

Located: `nclaw/mobile/ios/ShareExtension/`

**Flow:**
1. User shares content from Safari, Mail, Photos, etc.
2. iOS presents system share sheet with "Save to ɳClaw" action
3. ShareExtension process receives NSExtensionContext input items
4. Extension extracts text, URL, or image attachment
5. Extension writes shared data to App Group UserDefaults (key: `NCLAW_SHARED_CONTENT`)
6. Extension calls `nclaw://share` deep link to launch/activate main app
7. Main app receives deep link and routes to share-composer screen

**Implementation Details:**

- **ShareViewController.swift**: Handles NSExtensionContext, extracts attachments (text/URL/image), encodes as JSON payload, writes to UserDefaults
- **Info.plist**: Declares share service extension, activation rules (text/URL/image support)
- **MainInterface.storyboard**: UI for extension (minimal compose interface)
- **App Group**: `group.org.nself.nclaw.share` enables IPC between extension and main app
- **Entitlements**: `com.apple.security.application-groups` in app.json configures group access

### Configuration

In `app.json`:
```json
{
  "ios": {
    "appGroups": ["group.org.nself.nclaw.share"],
    "entitlements": {
      "com.apple.security.application-groups": ["group.org.nself.nclaw.share"]
    }
  }
}
```

### EAS Build

When building via EAS:
```bash
eas build --platform ios --profile release
```

Ensure:
- Apple Developer account has App Groups capability enabled
- Team ID is set in app.json plugin config
- Signing certificate includes share extension entitlement

## Android Implementation

### Intent Filter

Declared in `app.json` (Expo auto-generates AndroidManifest):

**Supported Actions:**
- `android.intent.action.SEND` — single item (text, URL, or image)
- `android.intent.action.SEND_MULTIPLE` — multiple images

**Supported MIME Types:**
- `text/plain` — text/URL shares
- `text/x-uri` — URI shares
- `image/*` — image shares

### Native Module

**ShareTargetModule.kt** (`android/ShareTargetModule.kt`):
- React Native native module
- Called on app startup
- Extracts Intent extras (EXTRA_TEXT, EXTRA_STREAM, EXTRA_SUBJECT)
- Serializes to JSON and stores in SharedPreferences
- Exposes `getSharedData()` Promise-based API

### Flow

1. User shares content from any app
2. Android system detects ɳClaw can handle the MIME type
3. User selects ɳClaw from share sheet
4. System launches MainActivity with Intent extras
5. React app initializes, calls `ShareTargetModule.getSharedData()`
6. Module extracts Intent extras, returns JSON payload
7. App routes to share-composer screen with pre-filled data

## Service Layer

### `services/shareTargetService.ts`

Public API:

```typescript
// Retrieve shared content (iOS UserDefaults or Android Intent)
getSharedContent(): Promise<SharedItem | null>

// Typed shared item
interface SharedItem {
  type: 'text' | 'url' | 'image';
  text?: string;
  url?: string;
  title?: string;
  imageUri?: string;
  mimeType?: string;
}

// Clear shared data after consuming
clearSharedContent(): Promise<void>

// Resolve image URI (download remote images to temp)
resolveImageUri(uri: string): Promise<string | null>

// Build deep link for share-composer navigation
buildShareDeepLink(item: SharedItem): string
```

## UI Layer

### Share Composer Screen (`app/share-composer.tsx`)

Modal screen displayed when share is received.

**Features:**
- Content preview card (text, title, image thumbnail)
- Topic selector (dropdown)
- Optional note field
- Save button (calls memory.quickAdd GraphQL mutation)
- Error handling + loading state

**Accessibility:**
- `accessibilityLabel` on all interactive elements
- Semantic color tokens from @nself/ui
- RTL support via @nself/i18n useDirection()

## App Initialization

### Root Layout (`app/+layout.tsx`)

On app startup:
1. After Sentry + OTel init
2. Before rendering children
3. Calls `getSharedContent()`
4. If shared item received, navigates to share-composer via deep link
5. Handles both cold-launch and hot-launch (app already in memory)

## Testing

### Manual iOS Test

1. Build and install on device/simulator
2. Open Safari, navigate to any web page
3. Share button → Share Sheet → "Save to ɳClaw"
4. ɳClaw opens with share-composer filled in
5. Verify URL pre-filled, optional note field works
6. Tap Save — shared URL added to memory

### Manual Android Test

1. Build and install on device/emulator
2. Open Files app, select any text file or image
3. Share → ɳClaw
4. App launches with share-composer
5. Verify text/image preview displays correctly
6. Verify topic selector works
7. Tap Save — verify content stored

### Cold-Launch Test

1. Force-quit ɳClaw app completely
2. Share content from external app
3. ɳClaw starts fresh (not in memory)
4. Verify share-composer opens automatically (not main chat screen)
5. Verify shared content is correctly pre-filled

### Image Handling

- **iOS**: Image copied to App Group temp directory via FileManager
- **Android**: Image URI resolved via ContentResolver (scoped storage compliant)
- **Download**: Remote images downloaded to `FileSystem.cacheDirectory` for display

## Permissions

### iOS
- None required (uses app container + App Groups)

### Android
- Implicit: receive SEND intents (no explicit permission needed)
- Implicit: read EXTERNAL_STORAGE for shared files (scoped storage handles this)

## Known Limitations

- **Single item per share**: Only first attachment is processed (SEND_MULTIPLE is detected but only first image is saved)
- **Temp file cleanup**: Images stored in cache directory; should be cleaned up after save
- **Offline**: Share composer requires connection to save (error shown if offline)
- **Background mode**: Extension runs in limited memory context; large images may fail

## Future Enhancements

- [ ] Support SEND_MULTIPLE to add multiple images per share
- [ ] Batch text extraction from documents (PDF, Doc)
- [ ] Preview text extraction from web article (Open Graph)
- [ ] Share history in share-composer (recent recipients)
- [ ] Scheduled task to clean up temp shared images

## Debugging

### iOS

Check App Group data:
```bash
# On simulator: navigate to container
~/Library/Developer/CoreSimulator/Devices/<device-id>/data/Containers/Shared/AppGroup/group.org.nself.nclaw.share/

# On device: use Console.app → Device → ɳClaw Process — filter for "ShareExtension"
```

### Android

Check SharedPreferences:
```bash
adb shell dumpsys meminfo org.nself.nclaw
adb shell "cat /data/data/org.nself.nclaw/shared_prefs/NCLAW_SHARED.xml"
```

Enable logging:
```typescript
// In shareTargetService.ts
console.log('[ShareTargetService]', ...)  // already present
```

## Related Tickets

- **T-P3-E4-W2-S3-T02**: Share composer screen implementation (RN version)
- **T-P3-E4-W2-S3-T04**: AI chat backend integration (processes shared content)
- **T-P3-E4-W2-S3-T09**: Full parity check across all mobile features
