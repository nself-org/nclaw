# nClaw for iOS/macOS

SwiftUI chat client for nClaw AI assistant. Connects to a self-hosted nSelf server running the `claw` plugin.

## Requirements

- Xcode 16+
- iOS 17+ / macOS 14+
- An nSelf server with the `claw` plugin installed (Max tier license)

## Project Setup

This scaffold does not include an `.xcodeproj` file. To build:

1. Open Xcode and create a new project: File > New > Project > App (SwiftUI)
2. Set the product name to `NClaw` and bundle identifier to `org.nself.nclaw`
3. Set the deployment target to iOS 17.0 / macOS 14.0
4. Replace the generated source files with the files in `NClaw/`
5. Build and run

Once `libnclaw` FFI bindings are ready, the project will add a Swift Package dependency for the shared Rust library.

## Architecture

```text
NClaw/
  NClawApp.swift         App entry point
  ContentView.swift      Tab navigation (Chat + Settings)
  Views/
    ChatView.swift       Message list + input field
    SettingsView.swift   Server URL and API key configuration
  Models/
    Message.swift        Chat message model
  Services/
    ClawClient.swift     HTTP client for the claw plugin API
```

## Configuration

Copy `.env.example` for reference. At runtime, the server URL and API key are entered in the Settings tab and persisted via `UserDefaults`.

## Server Setup

```bash
cd your-nself-project
nself plugin install ai claw mux
nself build && nself start
```

The app connects to `{server_url}/claw/chat` via POST with a JSON body `{"message": "..."}`.
