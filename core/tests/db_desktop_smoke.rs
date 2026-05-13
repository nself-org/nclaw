//! Smoke tests for the desktop DB layer scaffold.
//!
//! These tests do NOT require a real Postgres binary or WASM runtime.
//! They verify that `DesktopDb` constructs without panicking and that
//! the placeholder `start()` returns the expected error shape until
//! S16.T01b integrates the real engines.

use libnclaw::db::desktop::DesktopDb;
use std::path::Path;

#[test]
fn new_default_constructs() {
    let db = DesktopDb::new_default("/tmp/nclaw-test".into());
    let name = db.engine_name();
    assert!(
        ["pglite", "embedded-pg"].contains(&name),
        "unexpected engine name: {name}"
    );
}

#[test]
fn pglite_engine_name_is_correct() {
    let db = DesktopDb::new_pglite("/tmp/nclaw-test".into());
    assert_eq!(db.engine_name(), "pglite");
}

#[test]
fn pglite_start_returns_pending_error() {
    let mut db = DesktopDb::new_pglite("/tmp/nclaw-test".into());
    let res = db.start(Path::new("/tmp/nclaw-test"));
    assert!(res.is_err(), "pglite WASM not yet integrated; expected Err");
    let msg = res.unwrap_err().to_string();
    assert!(
        msg.contains("pending"),
        "error should mention 'pending'; got: {msg}"
    );
}

#[test]
fn pglite_stop_is_infallible() {
    let mut db = DesktopDb::new_pglite("/tmp/nclaw-test".into());
    assert!(db.stop().is_ok(), "stop() before start() must succeed");
}
