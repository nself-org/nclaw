//! Mobile SQLite engine with sqlite-vec extension.
//!
//! Per Decision #4, mobile uses SQLite + sqlite-vec for vector embeddings.
//! Static-library bundling for 7 mobile triples lands in S16.T02b CI ticket.

pub mod sqlite_engine;

pub use sqlite_engine::{MobileDb, MobileSqliteEngine};
