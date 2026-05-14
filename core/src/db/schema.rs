/// Schema definitions for nClaw local database.
/// Canonical SQL strings for both PostgreSQL (pglite) and SQLite variants.
/// Source of truth: nclaw/protocol/sync-protocol.md

pub const SCHEMA_PG_V1: &str = include_str!("../../migrations/0001_initial_schema.sql");
pub const SCHEMA_SQLITE_V1: &str = include_str!("../../migrations/0001_initial_schema.sqlite.sql");

use crate::error::CoreError;

/// Apply PostgreSQL schema (pglite desktop) to an executor.
/// The executor callback receives the full schema SQL and must handle transactions/idempotency.
pub fn apply_pg<F>(execute: F) -> Result<(), CoreError>
where
    F: FnOnce(&str) -> Result<(), String>,
{
    execute(SCHEMA_PG_V1)
        .map_err(|e| CoreError::Other(format!("pg schema apply failed: {}", e)))
}

/// Apply SQLite schema (mobile) to an executor.
/// The executor callback receives the full schema SQL and must handle transactions/idempotency.
pub fn apply_sqlite<F>(execute: F) -> Result<(), CoreError>
where
    F: FnOnce(&str) -> Result<(), String>,
{
    execute(SCHEMA_SQLITE_V1)
        .map_err(|e| CoreError::Other(format!("sqlite schema apply failed: {}", e)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_schema_constants_not_empty() {
        assert!(!SCHEMA_PG_V1.is_empty(), "pg schema should not be empty");
        assert!(!SCHEMA_SQLITE_V1.is_empty(), "sqlite schema should not be empty");
    }

    #[test]
    fn test_schema_pg_contains_migrations_table() {
        assert!(
            SCHEMA_PG_V1.contains("migrations"),
            "pg schema must define migrations table"
        );
    }

    #[test]
    fn test_schema_sqlite_contains_migrations_table() {
        assert!(
            SCHEMA_SQLITE_V1.contains("migrations"),
            "sqlite schema must define migrations table"
        );
    }

    #[test]
    fn test_schema_pg_contains_np_topics() {
        assert!(
            SCHEMA_PG_V1.contains("np_topics"),
            "pg schema must define np_topics table"
        );
    }

    #[test]
    fn test_schema_sqlite_contains_np_topics() {
        assert!(
            SCHEMA_SQLITE_V1.contains("np_topics"),
            "sqlite schema must define np_topics table"
        );
    }
}
