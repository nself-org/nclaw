//! Smoke tests for the migrations runner.
//! Tests the versioning logic, idempotency, and engine selection.

use libnclaw::db::migrate::{run, Engine, MigrationRunner};
use libnclaw::error::CoreError;

/// Mock runner that simulates database operations without a real database.
struct MockRunner {
    version: i32,
    sqls_applied: Vec<String>,
    should_fail_on: Option<String>, // "current_version", "apply_sql", or "record_version"
}

impl MockRunner {
    fn new(initial_version: i32) -> Self {
        Self {
            version: initial_version,
            sqls_applied: vec![],
            should_fail_on: None,
        }
    }
}

impl MigrationRunner for MockRunner {
    fn current_version(&mut self) -> Result<i32, CoreError> {
        if self.should_fail_on.as_deref() == Some("current_version") {
            Err(CoreError::Other("mock version query failure".to_string()))
        } else {
            Ok(self.version)
        }
    }

    fn apply_sql(&mut self, sql: &str) -> Result<(), CoreError> {
        if self.should_fail_on.as_deref() == Some("apply_sql") {
            Err(CoreError::Other("mock SQL execution failure".to_string()))
        } else {
            self.sqls_applied.push(sql.to_string());
            Ok(())
        }
    }

    fn record_version(&mut self, v: i32, _name: &str) -> Result<(), CoreError> {
        if self.should_fail_on.as_deref() == Some("record_version") {
            Err(CoreError::Other("mock version record failure".to_string()))
        } else {
            self.version = v;
            Ok(())
        }
    }
}

#[test]
fn applies_all_migrations_from_zero() {
    let mut runner = MockRunner::new(0);
    let applied = run(&mut runner, Engine::Pg).expect("migrations should succeed");
    assert_eq!(applied, 2, "should apply 2 migrations from version 0");
    assert_eq!(runner.version, 2, "final version should be 2");
    assert_eq!(
        runner.sqls_applied.len(),
        2,
        "should have applied 2 SQL statements"
    );
}

#[test]
fn skips_already_applied_migrations() {
    let mut runner = MockRunner::new(1);
    let applied = run(&mut runner, Engine::Pg).expect("migrations should succeed");
    assert_eq!(applied, 1, "should apply only migration 2");
    assert_eq!(runner.version, 2, "final version should be 2");
    assert_eq!(
        runner.sqls_applied.len(),
        1,
        "should have applied 1 SQL statement"
    );
}

#[test]
fn is_idempotent_when_all_migrations_applied() {
    let mut runner = MockRunner::new(2);
    let applied = run(&mut runner, Engine::Pg).expect("migrations should succeed");
    assert_eq!(applied, 0, "should apply 0 migrations when all are done");
    assert_eq!(runner.version, 2, "version should remain 2");
    assert!(
        runner.sqls_applied.is_empty(),
        "should not apply any SQL statements"
    );
}

#[test]
fn sqlite_engine_uses_sqlite_sql_variant() {
    let mut runner = MockRunner::new(0);
    let _ = run(&mut runner, Engine::Sqlite).expect("migrations should succeed");

    assert!(!runner.sqls_applied.is_empty(), "should apply migrations");

    // SQLite migration 0001 should contain SQLite-specific syntax (PRAGMA, CREATE VIRTUAL TABLE)
    let first_sql = &runner.sqls_applied[0];
    assert!(
        first_sql.contains("PRAGMA") || first_sql.contains("VIRTUAL TABLE"),
        "SQLite variant should contain PRAGMA or VIRTUAL TABLE directives"
    );
}

#[test]
fn pg_engine_uses_postgres_sql_variant() {
    let mut runner = MockRunner::new(0);
    let _ = run(&mut runner, Engine::Pg).expect("migrations should succeed");

    assert!(!runner.sqls_applied.is_empty(), "should apply migrations");

    // Postgres migration 0001 should contain CREATE EXTENSION
    let first_sql = &runner.sqls_applied[0];
    assert!(
        first_sql.contains("EXTENSION"),
        "PostgreSQL variant should contain CREATE EXTENSION directives"
    );
}

#[test]
fn propagates_current_version_errors() {
    let mut runner = MockRunner::new(0);
    runner.should_fail_on = Some("current_version".to_string());

    let result = run(&mut runner, Engine::Pg);
    assert!(
        result.is_err(),
        "should propagate error from current_version()"
    );
}

#[test]
fn propagates_apply_sql_errors() {
    let mut runner = MockRunner::new(0);
    runner.should_fail_on = Some("apply_sql".to_string());

    let result = run(&mut runner, Engine::Pg);
    assert!(result.is_err(), "should propagate error from apply_sql()");
}

#[test]
fn propagates_record_version_errors() {
    let mut runner = MockRunner::new(0);
    runner.should_fail_on = Some("record_version".to_string());

    let result = run(&mut runner, Engine::Pg);
    assert!(
        result.is_err(),
        "should propagate error from record_version()"
    );
}

#[test]
fn partial_migrations_leave_runner_at_failed_version() {
    let mut runner = MockRunner::new(0);
    runner.should_fail_on = Some("record_version".to_string());

    let _ = run(&mut runner, Engine::Pg);
    // Runner version is only incremented on successful record_version,
    // which failed, so version should remain 0.
    assert_eq!(
        runner.version, 0,
        "version should not advance if record_version fails"
    );
}

#[test]
fn migration_count_matches_schema() {
    let mut runner = MockRunner::new(0);
    let applied = run(&mut runner, Engine::Pg).expect("migrations should succeed");
    // Current schema has 2 migrations (0001 and 0002).
    // If this test fails, it means migrations/ added a new file but MIGRATIONS constant wasn't updated.
    assert_eq!(applied, 2, "migration count should match schema definition");
}
