# nClaw Desktop Daemon

macOS menu bar app that acts as a local bridge between the nself-claw server and the user's machine. Provides file access, shell execution, clipboard, screenshot, and browser integration through a local HTTP server and WebSocket connection.

## Requirements

- macOS 13.0+ (Ventura)
- Xcode 15+ or Swift 5.9+ toolchain

## Build

```bash
cd claw/desktop
swift build
```

## Run

```bash
swift run nClaw
```

Or open in Xcode and run the nClaw scheme.

## Architecture

- **Local HTTP Server** on `127.0.0.1:7710` using Network.framework (NWListener). No third-party dependencies.
- **WebSocket Client** to nself-claw server using URLSessionWebSocketTask (built-in).
- **Menu Bar UI** using SwiftUI MenuBarExtra (macOS 13+).
- **Login Item** via SMAppService.

## Security

- HTTP server binds to localhost only. Not accessible from the network.
- Optional bearer token authentication for HTTP endpoints.
- All file operations sandboxed to user-configured directories (defaults to ~/Documents).
- Shell commands require explicit user approval via native system dialog.
- JWT tokens stored in macOS Keychain.

## Endpoints

| Method | Path | Description |
| --- | --- | --- |
| GET | /health | Health check (no auth required) |
| GET | /capabilities | Device capability report |
| POST | /files/read | Read file content |
| POST | /files/write | Write file content |
| POST | /files/list | List directory contents |
| POST | /files/delete | Delete file |
| POST | /files/mkdir | Create directory |
| POST | /shell/exec | Execute shell command (requires approval) |
| GET | /clipboard/read | Read clipboard |
| POST | /clipboard/write | Write to clipboard |
| POST | /screenshot | Capture screen (returns base64 PNG) |
| POST | /browser/navigate | Navigate browser (stub) |
| POST | /browser/execute | Execute browser script (stub) |
