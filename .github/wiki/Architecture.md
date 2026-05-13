# nClaw v1.1.1 Architecture Decision Record (ADR)

**Status:** LOCKED 2026-05-11 (P101 STORM)
**Scope:** nClaw monorepo (`nclaw/`) — desktop + mobile + core + protocol
**Target release:** v1.1.1
**Supersedes:** v1.1.0 Flutter-desktop architecture (archived to `nclaw/legacy-flutter-desktop/`)

This ADR captures the twelve architecture decisions that govern the nClaw v1.1.1 implementation. Each decision is canonical: any divergence in code, docs, or planning is wrong and must be reconciled against this record. The pre-v1.1.1 component overview (Flutter + libnclaw single-tree) is preserved in git history; the architecture below replaces it.

---

## ADR-001 — Framework Split: Tauri 2 desktop + Flutter mobile

**Decision.** Desktop ships on Tauri 2; mobile ships on Flutter. Both share a Rust core compiled to native bindings for each platform. The v1.1.0 Flutter desktop codebase is archived to `nclaw/legacy-flutter-desktop/` and removed entirely in v1.2.0.

**Rationale.** Tauri 2 gives the desktop tier native OS integration, smaller binaries, and direct access to system keychain, file system, and local LLM runtimes. Flutter retains the mobile tier where it leads on cross-platform fidelity (iOS + Android from one tree). A shared Rust core keeps business logic, sync, and LLM-runtime glue identical across platforms.

**Consequences.** Two UI codebases (React/TS on desktop, Dart on mobile). The Rust core absorbs the cost — both sides call into it via type-safe FFI.

---

## ADR-002 — Repo Structure: nclaw/ becomes a monorepo

**Decision.** `nclaw/` is restructured into a monorepo:

- `nclaw/desktop/` — Tauri 2 + React + Vite + Tailwind. `src-tauri/` holds Rust glue.
- `nclaw/mobile/` — Flutter (v1.1.0 refactored to call the Rust core via `flutter_rust_bridge`).
- `nclaw/core/` — Rust crate `nclaw-core`. Workspace member. FFI-compiled to iOS `.framework`, Android `.so`, and a Tauri native module.
- `nclaw/protocol/` — Sync schema + IDL (proto / OpenAPI / json-schema).
- `nclaw/legacy-flutter-desktop/` — frozen v1.1.0 Flutter desktop. README explains the Tauri 2 migration path.

**Consequences.** The current `nclaw/` (Flutter mobile app) is `git mv`'d into `nclaw/mobile/` during S12.T02. Existing wiki pages live at the repo root until that restructure completes.

---

## ADR-003 — Local LLM Runtime: llama.cpp (FFI) primary, Ollama optional

**Decision.** `llama.cpp` via FFI is the primary local-LLM runtime. Ollama is supported as an optional alternative backend. Default model family is **Llama 3.2** (Meta) for tiers T0–T3; **Qwen 2.5** ships as bundled alternative with a clear UI swap.

**License note.** Llama Community License is acceptable for nSelf today (no MAU > 700M concern). Revisit if scale changes.

---

## ADR-004 — Local Database: pglite on desktop, SQLite + sqlite-vec on mobile

**Decision.**

- **Desktop:** pglite (Postgres compiled to WASM via wasmtime). Same schema as server. Fallback: embedded-postgres if pglite issues surface during S16.
- **Mobile:** SQLite + sqlite-vec (only viable option — real Postgres won't run on iOS/Android).

The sync layer translates between the two schemas where they diverge.

---

## ADR-005 — Sync Engine: Event-log + LWW + Hasura subscriptions

**Decision.** Custom event-log with last-write-wins per entity, Hasura subscriptions for fan-out, and an offline queue for local-first writes. **Not** full CRDT — this is single-user multi-device, not collaborative. Upgrade path to CRDT is reserved for v1.3.x if real conflicts emerge.

---

## ADR-006 — Cross-language Bindings

**Decision.**

- **Tauri ↔ React TS:** `tauri-specta` + `ts-rs` for type-safe Rust↔TypeScript bindings.
- **Flutter ↔ Rust:** `flutter_rust_bridge`.

Both binding stacks are generated from the same `nclaw-core` crate.

---

## ADR-007 — Credential Vault: server of record, OS keychain mirror, per-device keypair

**Decision.**

- **Server of record:** encrypted blob storage in the `plugins-pro/vault` extension.
- **Local mirror:** OS keychain — `keyring-rs` on desktop, `flutter_secure_storage` on mobile.
- **Per-device keypair:** generated on first install. Private key stays in the local keychain. Public key is registered with the server.
- **Encryption envelope:** server holds the blob encrypted with a per-user master key, then wrapped per-device via the public key.

---

## ADR-008 — Existing v1.1.0 Flutter Desktop: archive, do not migrate

**Decision.** The v1.1.0 Flutter desktop has no production users, so there is no migration burden. v1.1.1 ships the Tauri 2 desktop alongside the legacy archive. v1.2.0 removes the legacy archive entirely.

---

## ADR-009 — Device-Aware Local LLM Defaults

**Decision.** First-run device fingerprinting + benchmark selects a tier automatically.

### Tier matrix

| Tier | Profile | Default model | Quant | Size | Target tok/s |
|------|---------|---------------|-------|------|--------------|
| T0 — Ultra-light | Android 4GB · iPhone 11/12 low-power · old netbooks | Qwen 2.5 0.5B | Q4_K_M | ~350 MB | 15–30 |
| T1 — Light | iPhone 13/14 · mid Android (6-8GB) · 8GB Intel laptops | Llama 3.2 1B | Q4_K_M | ~700 MB | 20–40 |
| T2 — Standard (sweet spot) | M1/M2 base · iPhone 15/16 · iPad Air · 16GB laptops · Snapdragon 8 Gen 2+ | Llama 3.2 3B | Q4_K_M | ~2 GB | 25–50 (60–100 on Apple Silicon) |
| T3 — Capable | M1/M2 Pro · 16-32GB workstations · gaming PCs (8GB+ VRAM) | Llama 3.1 8B | Q4_K_M | ~4.5 GB | 30–80 |
| T4 — Heavy (opt-in only) | M2/M3/M4 Max/Ultra · 64GB+ workstations · multi-GPU rigs | Qwen 2.5 14B or Llama 3.1 70B | Q4_K_M | 8–40 GB | 15–40 |

### Decision algorithm

1. Probe device: OS, arch, CPU class, RAM, GPU vendor + VRAM, NPU, free disk.
2. Score device → tier T0..T4.
3. Background-download the tier default.
4. First-run benchmark (60s): warmup + 200-token completion.
5. Measure tok/s, p99 latency, RAM peak, thermal throttle.
6. If benchmark falls below target → auto-downgrade one tier.
7. If benchmark far exceeds target → offer a one-time upgrade prompt.
8. Cache result in config; re-benchmark monthly or on hardware change.
9. Mobile dampers: low-power mode drops one tier; battery below 30% with charger disconnected disables local LLM (user-configurable).

### Role-specific models

Users may configure separate models per role: Chat, Summarizer, Embedder, Code (developer mode). T0/T1 share one model across roles. T2+ may run a dedicated embedder (e.g., BGE-small).

---

## ADR-010 — Sync Direction: Local-first with eventual consistency

**Decision.** Writes land locally first for instant UX. The offline queue replicates to the server. The server fans out to other devices via Hasura subscriptions. Conflict resolution is LWW per entity with a manual-resolve UI hook for the rare cases where it matters.

---

## ADR-011 — Plugin Integration: server-side over HTTPS, MCP-style protocol

**Decision.** The local app calls server plugins (calendar, email, browser, news, budget, voice) over HTTPS against the user's nSelf instance. MCP-style protocol. There is **no local plugin runtime in v1.1.1** — that is deferred to v1.2.x. The v1.1.1 groundwork is the local LLM, sync engine, and vault.

---

## ADR-012 — Versioning: monorepo lockstep at v1.1.1

**Decision.** The nclaw monorepo ships a single version `v1.1.1` across desktop, mobile, core, and protocol. Independent versioning may be introduced later if a real need emerges.

---

## References

- Source decisions: `.claude/phases/current/p101-storm/architecture-decisions.md`
- Three-Surface Model: nSelf PPI § Three-Surface Model
- Plugin-First Doctrine: nSelf PPI § Plugin-First Development
- nSelf-First Doctrine: `.claude/docs/doctrines/nself-first.md`
- Prior architecture (v1.1.0 Flutter component overview): preserved in git history; pre-restructure state.
