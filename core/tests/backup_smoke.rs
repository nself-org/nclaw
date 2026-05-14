//! Smoke tests for backup/restore and scope helpers.

use libnclaw::db::backup::{BackupRecord, from_jsonl, to_jsonl};
use libnclaw::db::scope::AccountScope;

#[test]
fn jsonl_roundtrip() {
    let records = vec![
        BackupRecord {
            table: "np_topics".into(),
            row: serde_json::json!({"id": "abc", "path": "work"}),
        },
        BackupRecord {
            table: "np_messages".into(),
            row: serde_json::json!({"id": "def", "content": "hi"}),
        },
    ];
    let jsonl_bytes = to_jsonl(&records);
    let parsed = from_jsonl(jsonl_bytes.as_bytes()).expect("parse failed");
    assert_eq!(parsed.len(), 2);
    assert_eq!(parsed[0].table, "np_topics");
    assert_eq!(parsed[1].row["content"], "hi");
}

#[test]
fn jsonl_skips_empty_lines() {
    let bytes = b"\n{\"table\":\"a\",\"row\":{}}\n\n{\"table\":\"b\",\"row\":{}}\n";
    let parsed = from_jsonl(bytes).expect("parse failed");
    assert_eq!(parsed.len(), 2);
}

#[test]
fn account_scope_sql_filter() {
    let scope = AccountScope::nclaw();
    assert_eq!(scope.sql_filter(), "source_account_id = 'nclaw'");
}

#[test]
fn account_scope_sql_filter_quote_escaping() {
    let scope = AccountScope::for_app("test'app");
    assert_eq!(scope.sql_filter(), "source_account_id = 'test''app'");
}

#[test]
fn account_scope_constants() {
    assert_eq!(AccountScope::nclaw().source_account_id, "nclaw");
    assert_eq!(AccountScope::primary().source_account_id, "primary");
}

#[test]
fn account_scope_custom_app() {
    let scope = AccountScope::for_app("my-custom-app");
    assert_eq!(scope.source_account_id, "my-custom-app");
    assert_eq!(scope.to_string(), "my-custom-app");
}

#[test]
fn backup_record_serialization() {
    let record = BackupRecord {
        table: "np_topics".into(),
        row: serde_json::json!({"id": "x", "title": "Test"}),
    };
    let json_str = serde_json::to_string(&record).expect("serialize failed");
    assert!(json_str.contains("np_topics"));
    assert!(json_str.contains("Test"));
}
