//! DB backup + restore. JSONL format — one record per line, table name prefix.
//!
//! Used by pglite desktop engine for local snapshots and restore operations.
//! Format: `{"table":"np_topics","row":{...}}\n{"table":"np_messages","row":{...}}\n`

use crate::error::CoreError;
use serde::{Serialize, Deserialize};

/// A single backed-up database record.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupRecord {
    /// Table name (e.g., "np_topics", "np_messages")
    pub table: String,
    /// Row data as JSON object
    pub row: serde_json::Value,
}

/// Trait for database backup and restore operations.
#[async_trait::async_trait]
pub trait Backup: Send + Sync {
    /// Stream all rows from the local DB as a Vec of BackupRecord.
    /// Implementations may chunk, but the simplest is dump-all.
    async fn dump(&self) -> Result<Vec<BackupRecord>, CoreError>;

    /// Apply records to the DB. Existing rows with matching PK are upserted.
    /// Returns the count of records restored.
    async fn restore(&self, records: &[BackupRecord]) -> Result<u32, CoreError>;
}

/// Serialize backup records to JSONL format (one JSON object per line).
pub fn to_jsonl(records: &[BackupRecord]) -> String {
    records
        .iter()
        .filter_map(|r| serde_json::to_string(r).ok())
        .collect::<Vec<_>>()
        .join("\n")
}

/// Parse JSONL format bytes into backup records (skips empty lines).
pub fn from_jsonl(bytes: &[u8]) -> Result<Vec<BackupRecord>, CoreError> {
    let s = std::str::from_utf8(bytes)
        .map_err(|e| CoreError::Other(format!("UTF-8 decode: {}", e)))?;

    s.lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| {
            serde_json::from_str::<BackupRecord>(l)
                .map_err(|e| CoreError::Other(format!("JSONL parse: {}", e)))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jsonl_serialize() {
        let records = vec![
            BackupRecord {
                table: "np_topics".into(),
                row: serde_json::json!({"id": "abc", "title": "Work"}),
            },
            BackupRecord {
                table: "np_messages".into(),
                row: serde_json::json!({"id": "msg1", "content": "Hello"}),
            },
        ];
        let jsonl = to_jsonl(&records);
        assert!(jsonl.contains("\"table\":\"np_topics\""));
        assert!(jsonl.contains("\"table\":\"np_messages\""));
    }

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
        let jsonl = to_jsonl(&records);
        let parsed = from_jsonl(jsonl.as_bytes()).expect("parse failed");
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
    fn jsonl_invalid_utf8() {
        let bytes = b"\xff\xfe invalid utf8";
        let result = from_jsonl(bytes);
        assert!(result.is_err());
    }
}
