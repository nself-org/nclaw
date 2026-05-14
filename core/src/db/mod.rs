//! Database layer for nClaw.
//!
//! Desktop: pglite (Postgres-on-WASM, Decision #4 default) with embedded-postgres fallback.
//! Mobile: sqlite + sqlite-vec (separate module, gated by mobile-sqlite feature).

pub mod desktop;

#[cfg(feature = "mobile-sqlite")]
pub mod mobile;
