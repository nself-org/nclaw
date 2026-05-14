#![cfg(feature = "mobile-sqlite")]

use libnclaw::db::mobile::MobileDb;
use std::path::Path;
use tempfile::NamedTempFile;

#[test]
fn test_mobile_sqlite_open() {
    let mut db = MobileDb::new();

    // Create a temporary database file.
    let temp = NamedTempFile::new().expect("failed to create temp file");
    let path = temp.path();

    // Open the database.
    let result = db.open(path);
    assert!(
        result.is_ok(),
        "Failed to open mobile SQLite database: {:?}",
        result
    );

    // Verify engine name.
    assert_eq!(db.engine_name(), "sqlite+vec");
}

#[test]
fn test_mobile_sqlite_in_memory() {
    let mut db = MobileDb::new();

    // Create an in-memory database (SQLite standard :memory: path).
    let result = db.open(Path::new(":memory:"));
    assert!(
        result.is_ok(),
        "Failed to open in-memory SQLite database: {:?}",
        result
    );

    assert_eq!(db.engine_name(), "sqlite+vec");
}
