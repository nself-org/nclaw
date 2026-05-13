# ADR-0004: Local Database (pglite Desktop, SQLite Mobile)

**Status:** Accepted 2026-05-11  
**Context:** Each platform needs offline-first local storage with schema parity to server.  
**Decision:** Desktop uses pglite (WASM Postgres), mobile uses SQLite + sqlite-vec.  

## Context

Offline-first sync requires a local database. Desktop can run a heavier runtime; mobile must be lightweight. Server schema uses Postgres; aligning local schemas where possible reduces translation logic.

## Decision

- **Desktop:** pglite (Postgres compiled to WASM via wasmtime). Same schema as server where possible. Fallback to embedded-postgres if pglite issues surface during S16.
- **Mobile:** SQLite + sqlite-vec extension (only viable option; real Postgres cannot run on iOS/Android).

Sync layer translates between schemas where they diverge (e.g., SQLite lacks jsonb, ltree, pgvector).

## Rationale

- **pglite on desktop:** Familiar Postgres semantics, minimal deployment (single WASM binary), system-level caching via wasmtime.
- **SQLite on mobile:** Minimal footprint (single file), fast startup, mature vector extension.
- **Schema alignment:** Reduces sync translation; Postgres SQL can be ported with minimal changes for desktop.

## Consequences

**Positive:**
- Desktop users get a familiar Postgres environment for advanced queries.
- Mobile users benefit from SQLite's simplicity and reliability.

**Negative:**
- Two database backends require testing both sync paths.
- Postgres-specific features (ltree hierarchies, JSON operators, custom types) must be emulated on mobile.

## Alternatives Considered

- **SQLite everywhere:** Simpler sync logic, but less powerful query engine on desktop.
- **Embedded Postgres on both:** Heavier mobile footprint; faster startup on desktop may not justify the tradeoff.

## References

- pglite: https://electricsql.com/pglite  
- sqlite-vec: https://github.com/asg017/sqlite-vec  
- wasmtime: https://wasmtime.dev/
