//! Mobile SQLite engine with sqlite-vec extension.
//!
//! Per Decision #4, mobile uses SQLite + sqlite-vec for vector embeddings.
//! Static-library bundling for 7 mobile triples lands in S16.T02b CI ticket.

pub mod first_run;
pub mod sqlite_engine;

pub use first_run::{fetch_or_generate_db_key, DbKeyResult, DB_KEY_ACCOUNT};
pub use sqlite_engine::{MobileDb, MobileSqliteEngine};
