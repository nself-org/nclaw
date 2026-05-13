//! Database layer for nClaw.
//!
//! Desktop: pglite (Postgres-on-WASM, Decision #4 default) with embedded-postgres fallback.
//! Mobile: sqlite + sqlite-vec (separate module, future sub-ticket).

pub mod desktop;
