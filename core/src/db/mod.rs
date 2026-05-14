//! Database layer for nClaw.
//!
//! Desktop: pglite (Postgres-on-WASM, Decision #4 default) with embedded-postgres fallback.
//! Mobile: sqlite + sqlite-vec (separate module, gated by mobile-sqlite feature).

pub mod backup;
pub mod dal;
pub mod desktop;
pub mod encryption;
pub mod migrate;
pub mod scope;
pub mod telemetry;
pub mod vector;

#[cfg(feature = "mobile-sqlite")]
pub mod mobile;
