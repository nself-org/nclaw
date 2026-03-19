# nClaw for Android

Kotlin + Jetpack Compose chat client for nClaw AI assistant. Connects to a self-hosted nSelf server running the `claw` plugin.

## Requirements

- Android Studio Ladybug (2024.2) or later
- JDK 17+
- Android SDK 35
- Min SDK 26 (Android 8.0)
- An nSelf server with the `claw` plugin installed (Max tier license)

## Build

```bash
cd apps/android
./gradlew assembleDebug
```

Or open the `apps/android/` directory in Android Studio and run from the IDE.

## Architecture

```text
app/src/main/java/org/nself/nclaw/
  MainActivity.kt                 Compose Activity with bottom navigation
  ui/
    ChatScreen.kt                 Message list + input composable
    ChatViewModel.kt              Chat state management (ViewModel + StateFlow)
    SettingsScreen.kt             Server URL and API key configuration
  data/
    Message.kt                   Chat message data class
    ClawClient.kt                HTTP client (OkHttp) for the claw plugin API
```

## Dependencies

- Jetpack Compose with Material 3
- OkHttp for networking
- AndroidX ViewModel for state management

## Configuration

Copy `.env.example` for reference. At runtime, the server URL and API key are entered in the Settings screen and persisted via `SharedPreferences`.

## Server Setup

```bash
cd your-nself-project
nself plugin install ai claw mux
nself build && nself start
```

The app connects to `{server_url}/claw/chat` via POST with a JSON body `{"message": "..."}`.
