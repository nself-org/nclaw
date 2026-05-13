# ɳClaw Client Repo

Welcome to the ɳClaw client repository. This contains the native applications (desktop, mobile) and shared Rust core for the personal AI assistant platform.

## Quick Links

- **[Developer Setup Guide](dev-setup)** — Bootstrap on macOS, Linux, Windows, iOS, Android (<30 min)
- **[ARCHITECTURE](ARCHITECTURE)** — System design and 12 key decisions
- **[README](../../../README.md)** — Project overview, setup, building

## Architecture

ɳClaw v1.1.1 is a monorepo with four main components:

- **Desktop** (Tauri 2 + React) — macOS, Linux, Windows
- **Mobile** (Flutter) — iOS, Android
- **Core** (Rust) — Shared business logic, sync, encryption
- **Protocol** — Sync schema and IDL definitions

All components ship together at version `v1.1.1`. See [ARCHITECTURE](ARCHITECTURE) for design details and the 12 ADRs that govern the implementation.

## Contributing

This is the open-source client repo. Backend services (plugins, server) run on a self-hosted nSelf instance. See the top-level README for contribution guidelines.
