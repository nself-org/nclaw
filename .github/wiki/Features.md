# Features

## AI Chat

Multi-turn conversations with full context management. Supports streaming responses, conversation branching, and message editing. Context window is managed automatically — older messages are summarized and compressed when nearing the limit.

## Memory and Context

Persistent memory across sessions. The AI remembers user preferences, facts, and prior interactions. Memory entries can be viewed, edited, and deleted. Context injection allows pinned knowledge to be included in every conversation.

## Tool Calls

The AI can invoke tools to take actions:

| Tool | Description |
|------|-------------|
| Web search | Search the web and retrieve results |
| File read/write | Read and write files on the server |
| Code execution | Run code in a sandboxed environment |
| Shell commands | Execute commands on the backend host |
| Browser automation | Control a real browser via nself-browser (CDP) |
| Calendar/email | Connect to external services via nself-mux |

Tool results are fed back to the AI automatically; the AI can chain multiple tool calls in a single turn.

## Personas

Custom AI personas with defined names, avatars, behavior rules, and knowledge scope. Each persona can be configured with:

- System prompt and behavior rules
- Restricted topic scope
- Preferred communication style
- Model selection (if multiple models are configured)

Personas can be shared with other users on the same backend.

## Proactive Intelligence

Background agents that monitor events and take action without being explicitly asked:

- **Scheduled tasks** — Run prompts or workflows on a schedule
- **Event triggers** — React to file changes, calendar events, incoming messages
- **Digest generation** — Periodic summaries of monitored data
- **Alerts** — Notify when conditions are met

## Voice

Speech-to-text input and text-to-speech output via the `nself-voice` Pro plugin:

- Continuous voice input mode with silence detection
- Real-time transcription displayed as you speak
- TTS playback with adjustable speed and voice selection
- Supported on iOS, Android, and macOS

## Browser Automation

AI-driven browser control via the `nself-browser` Pro plugin (Chrome DevTools Protocol):

- Navigate to URLs, click elements, fill forms
- Screenshot capture and visual reasoning
- JavaScript execution in the browser context
- Used for web scraping, automated workflows, and research tasks

## Multi-Modal Input

Beyond text, nClaw accepts:

- **Images** — Camera capture or photo library; AI describes and reasons about images
- **Files** — PDFs, documents, and code files as conversation context
- **Audio** — Voice notes transcribed before sending (distinct from live voice mode)

## E2E Encryption

Optional end-to-end encryption via libnclaw:

- X25519 Diffie-Hellman key exchange
- XChaCha20-Poly1305 authenticated encryption
- Message content encrypted on-device before reaching the backend
- Keys stored in platform keychain (iOS Keychain, Android Keystore, macOS Keychain)

When enabled, the backend stores only encrypted ciphertext — even the server operator cannot read message content.

## Multi-Platform

Single Flutter codebase targeting:

- iOS 16+
- Android 10+ (API 29+)
- macOS 12+
- Web (Chrome, Safari, Firefox)

Plus native clients:
- SwiftUI for iOS and macOS (in `apps/ios/`)
- Kotlin + Jetpack Compose for Android (in `apps/android/`)
