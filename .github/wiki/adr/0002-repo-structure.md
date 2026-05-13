# ADR-0002: Repo Structure (Monorepo)

**Status:** Accepted 2026-05-11  
**Context:** ɳClaw requires coordination across desktop (Tauri), mobile (Flutter), and core (Rust) codebases.  
**Decision:** Restructure `nclaw/` as a monorepo with four main directories plus legacy archive.  

## Context

v1.1.0 was a single Flutter codebase in `nclaw/`. This worked for mobile but didn't accommodate Tauri 2 desktop or a shared Rust library. Separating repos would introduce cross-repo dependency management overhead.

## Decision

Restructure into a monorepo:

- **`desktop/`** — Tauri 2 app (React + Vite + Tailwind, Rust glue in `src-tauri/`)
- **`mobile/`** — Flutter app (refactored to consume Rust core via flutter_rust_bridge)
- **`core/`** — Rust crate `nclaw-core` (Cargo workspace member, FFI-compiled to platform-native modules)
- **`protocol/`** — Sync schema + IDL (proto, OpenAPI, JSON schema definitions)
- **`legacy-flutter-desktop/`** — Frozen v1.1.0 Flutter desktop (read-only, README with migration guidance)

## Rationale

- **Single source of truth for business logic:** Rust core is compiled once, consumed by both platforms. No type duplication.
- **Unified versioning:** `v1.1.1` tags release desktop + mobile + core + protocol as a coherent unit.
- **Shared CI/CD:** One repo means one build matrix, one PR review process, one release checklist.
- **Clear separation:** Each subdirectory has its own language, build system, and test strategy, but all are tracked in git.

## Consequences

**Positive:**
- Easier to coordinate cross-platform changes (sync engine update touches `core/` only, both platforms get it).
- Single release cadence — no "mobile is v1.1.1, desktop is v1.1.0" confusion.

**Negative:**
- Larger repository (three languages, multiple build systems).
- Contributors must understand the whole monorepo structure, not just one platform.

## Alternatives Considered

- **Three separate repos** (desktop, mobile, core): Decoupled development, but FFI integration becomes fragile; version mismatch bugs are likely.
- **Monorepo with nested Cargo/Flutter workspace:** Tighter coupling, but three different build-system conventions in one tree.

## References

- Cargo workspaces: https://doc.rust-lang.org/cargo/reference/workspaces.html  
- Monorepo patterns: https://gomonorepo.org/
