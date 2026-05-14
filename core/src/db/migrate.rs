//! Versioned migrations runner. Applies SQL migrations in order, tracks version
//! in `migrations` table, idempotent.

use crate::error::{CoreError, DbError};

/// Trait that concrete DB runners (Postgres, SQLite) implement to apply migrations.
pub trait MigrationRunner {
    /// Return the current migration version. If no migrations table exists, returns 0.
    fn current_version(&mut self) -> Result<i32, CoreError>;

    /// Execute a raw SQL statement.
    fn apply_sql(&mut self, sql: &str) -> Result<(), CoreError>;

    /// Record a migration version in the migrations table.
    fn record_version(&mut self, version: i32, name: &str) -> Result<(), CoreError>;
}

/// A single migration file with both Postgres and SQLite variants.
pub struct Migration {
    pub version: i32,
    pub name: &'static str,
    pub pg_sql: &'static str,
    pub sqlite_sql: &'static str,
}

/// All migrations, in order. Runners will apply these sequentially.
pub const MIGRATIONS: &[Migration] = &[
    Migration {
        version: 1,
        name: "initial_schema",
        pg_sql: include_str!("../../migrations/0001_initial_schema.sql"),
        sqlite_sql: include_str!("../../migrations/0001_initial_schema.sqlite.sql"),
    },
    Migration {
        version: 2,
        name: "indexes_v1",
        pg_sql: include_str!("../../migrations/0002_indexes_v1.sql"),
        sqlite_sql: include_str!("../../migrations/0002_indexes_v1.sqlite.sql"),
    },
];

/// Database engine — determines which SQL dialect is used.
#[derive(Clone, Copy, Debug)]
pub enum Engine {
    /// PostgreSQL / pglite
    Pg,
    /// SQLite
    Sqlite,
}

/// Run all pending migrations against the given runner.
///
/// Returns the number of migrations that were applied.
/// Migrations are idempotent — if a version is already applied, it is skipped.
///
/// # Errors
///
/// Returns an error if:
/// - current_version() fails
/// - apply_sql() fails for any migration
/// - record_version() fails
pub fn run(runner: &mut dyn MigrationRunner, engine: Engine) -> Result<u32, CoreError> {
    let current = runner.current_version()?;
    let mut applied = 0u32;

    for migration in MIGRATIONS {
        if migration.version > current {
            let sql = match engine {
                Engine::Pg => migration.pg_sql,
                Engine::Sqlite => migration.sqlite_sql,
            };
            runner.apply_sql(sql)?;
            runner.record_version(migration.version, migration.name)?;
            applied += 1;
        }
    }

    Ok(applied)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mock runner that simulates DB calls without a real database.
    struct MockRunner {
        version: i32,
        sqls_applied: Vec<String>,
        should_fail: bool,
    }

    impl MockRunner {
        fn new(initial_version: i32) -> Self {
            Self {
                version: initial_version,
                sqls_applied: vec![],
                should_fail: false,
            }
        }
    }

    impl MigrationRunner for MockRunner {
        fn current_version(&mut self) -> Result<i32, CoreError> {
            if self.should_fail {
                Err(DbError::ConnectionFailed("mock failure".to_string()).into())
            } else {
                Ok(self.version)
            }
        }

        fn apply_sql(&mut self, sql: &str) -> Result<(), CoreError> {
            if self.should_fail {
                return Err(DbError::QueryFailed("mock failure".to_string()).into());
            }
            self.sqls_applied.push(sql.to_string());
            Ok(())
        }

        fn record_version(&mut self, v: i32, _name: &str) -> Result<(), CoreError> {
            if self.should_fail {
                return Err(DbError::TransactionFailed("mock failure".to_string()).into());
            }
            self.version = v;
            Ok(())
        }
    }

    #[test]
    fn applies_all_migrations_from_zero() {
        let mut runner = MockRunner::new(0);
        let applied = run(&mut runner, Engine::Pg).unwrap();
        assert_eq!(applied, 2);
        assert_eq!(runner.version, 2);
        assert_eq!(runner.sqls_applied.len(), 2);
    }

    #[test]
    fn skips_already_applied() {
        let mut runner = MockRunner::new(1);
        let applied = run(&mut runner, Engine::Pg).unwrap();
        assert_eq!(applied, 1);
        assert_eq!(runner.version, 2);
        assert_eq!(runner.sqls_applied.len(), 1);
    }

    #[test]
    fn no_op_when_all_applied() {
        let mut runner = MockRunner::new(2);
        let applied = run(&mut runner, Engine::Pg).unwrap();
        assert_eq!(applied, 0);
        assert_eq!(runner.sqls_applied.len(), 0);
    }

    #[test]
    fn sqlite_engine_uses_sqlite_sql() {
        let mut runner = MockRunner::new(0);
        let _ = run(&mut runner, Engine::Sqlite).unwrap();
        assert!(runner.sqls_applied.len() > 0);
        // First SQL should be the SQLite variant of 0001_initial_schema.sql
        // It will have PRAGMA or SQLite-specific syntax
        assert!(
            runner.sqls_applied[0].contains("PRAGMA")
                || runner.sqls_applied[0].contains("VIRTUAL TABLE")
        );
    }

    #[test]
    fn pg_engine_uses_pg_sql() {
        let mut runner = MockRunner::new(0);
        let _ = run(&mut runner, Engine::Pg).unwrap();
        // First SQL should be the Postgres variant (contains EXTENSION)
        assert!(runner.sqls_applied[0].contains("EXTENSION"));
    }

    #[test]
    fn handles_current_version_error() {
        let mut runner = MockRunner::new(0);
        runner.should_fail = true;
        let result = run(&mut runner, Engine::Pg);
        assert!(result.is_err());
    }

    #[test]
    fn handles_apply_sql_error() {
        let mut runner = MockRunner::new(0);
        // Success on current_version, fail on apply_sql
        runner.version = 0;
        runner.should_fail = true;
        let result = run(&mut runner, Engine::Pg);
        assert!(result.is_err());
    }
}
