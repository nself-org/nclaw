# ɳClaw Desktop — Settings Panel

The Settings window opens via **ɳClaw menu > Preferences** (Cmd+,) or the system tray. It has five sections, accessible from the left sidebar.

## Provider

Choose your AI backend: Local (llama.cpp), Ollama sidecar, OpenAI, Anthropic, or OpenRouter. Set the API base URL and, for cloud providers, an API key. Keys are passed to the backend for encryption — only the last four characters are shown after saving.

## Model

Assign models to four roles: Chat, Summarizer, Embedder, and Code. Available models are fetched from the configured provider. A tier badge shows whether the selection is auto-detected from your hardware or manually overridden.

## Vault

Shows whether this device is paired with the OS keychain. Tap **Re-pair device** to generate a new device keypair and register it. This is irreversible — re-pairing requires re-syncing encrypted data.

## Sync

Enter your nSelf server URL and license key to enable cloud sync and memory backup. Use **Test connection** to verify reachability before saving. Keys are masked after save; only the last four characters are visible.

## Advanced

- **Log level:** controls verbosity of the local log file (error / warn / info / debug / trace). Restart required.
- **Telemetry:** opt in/out of anonymous crash and usage reporting.
- **Check for updates:** controls whether the app checks for new releases on startup.
