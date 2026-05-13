# Desktop DB Fallback: Embedded Postgres

Documents the Decision #4 two-engine strategy for the nClaw desktop database layer
(`nclaw/core/src/db/desktop/`).

## Default: pglite (Postgres-on-WASM)

pglite runs Postgres entirely inside a WebAssembly sandbox via `wasmtime`. No system
Postgres binary is needed. The WASM bundle is small enough to ship inside the app bundle.

**Status:** engine surface scaffolded (S16.T01); WASM bundle integration lands in S16.T01b.

When integrated, pglite is preferred because:
- Ships as a self-contained binary (no external Postgres install required).
- Controlled upgrade path (WASM bundle is versioned alongside the app).
- Suitable for single-user desktop workloads.

## Fallback: Embedded Postgres

When pglite cannot host `pgvector` or `ltree` (both required by the nClaw memory graph),
compile the crate with `--features embedded-pg`. This activates `EmbeddedPgEngine`, which
launches a real `postgres` subprocess scoped to the user's app-data directory using
[`postgresql_embedded`](https://github.com/vasanthv/postgresql-embedded).

**Status:** engine surface scaffolded (S16.T01); subprocess lifecycle integration lands in S16.T01b.

## Feature Flags

| Flag | Effect |
|---|---|
| *(none)* | `new_default()` selects pglite |
| `pglite` | Explicitly marks pglite as selected (surface only; no additional code today) |
| `embedded-pg` | `new_default()` selects embedded-postgres; enables `dep:postgresql_embedded` |

Build with fallback:

```bash
cargo build --features embedded-pg
```

## Decision Tree (S16.T05 gate)

When the pglite WASM integration ships in S16.T01b, evaluate:

1. Does the bundled pglite WASM include `pgvector`?
2. Does it include `ltree`?

If both: keep `pglite` as the default. No action needed.

If either is missing: flip `new_default()` to call `new_embedded_pg()` unconditionally
(or make `embedded-pg` the default feature) and document the decision in
`nclaw/core/.claude/memory/decisions.md`.

## Data Directory

Both engines write to the path passed to `start(data_dir)`. On macOS this is:

```
~/Library/Application Support/io.nself.nclaw/db/
```

On Linux: `~/.local/share/io.nself.nclaw/db/`
On Windows: `%APPDATA%\io.nself.nclaw\db\`

The desktop app resolves this via `dirs::data_dir()` before calling `DesktopDb::start()`.

## Connection URL

`start()` returns a PostgreSQL connection URL (e.g. `postgresql://localhost:5432/nclaw`)
once the real engine is integrated. Downstream code (`crate::backend`) uses this URL to
initialise the connection pool.
