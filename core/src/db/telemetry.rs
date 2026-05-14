//! Database operation telemetry via atomic counters.
//!
//! Tracks query execution, migrations, searches, backups, and restores.
//! UI surfaces these metrics in Settings → Diagnostics.
//! Thread-safe via `std::sync::atomic::AtomicU64`.

use std::sync::atomic::{AtomicU64, Ordering};

/// Thread-safe telemetry counters for database operations.
#[derive(Default)]
pub struct DbTelemetry {
    /// Total SQL queries executed (includes both reads and writes).
    pub queries_executed: AtomicU64,

    /// SQL queries that failed (application or DB error).
    pub queries_failed: AtomicU64,

    /// Migrations applied since app launch (not cumulative lifetime).
    pub migrations_applied: AtomicU64,

    /// Vector similarity searches executed (for memory retrieval).
    pub vector_searches: AtomicU64,

    /// Database backups dumped to JSONL.
    pub backup_dumps: AtomicU64,

    /// Records restored from backup.
    pub restore_records: AtomicU64,
}

impl DbTelemetry {
    /// Snapshot all counters into a non-atomic struct.
    /// Safe to call concurrently; returns a consistent point-in-time view.
    pub fn snapshot(&self) -> DbTelemetrySnapshot {
        DbTelemetrySnapshot {
            queries_executed: self.queries_executed.load(Ordering::Relaxed),
            queries_failed: self.queries_failed.load(Ordering::Relaxed),
            migrations_applied: self.migrations_applied.load(Ordering::Relaxed),
            vector_searches: self.vector_searches.load(Ordering::Relaxed),
            backup_dumps: self.backup_dumps.load(Ordering::Relaxed),
            restore_records: self.restore_records.load(Ordering::Relaxed),
        }
    }

    /// Increment queries_executed by 1.
    pub fn increment_queries_executed(&self) {
        self.queries_executed.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment queries_failed by 1.
    pub fn increment_queries_failed(&self) {
        self.queries_failed.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment migrations_applied by 1.
    pub fn increment_migrations_applied(&self) {
        self.migrations_applied.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment vector_searches by 1.
    pub fn increment_vector_searches(&self) {
        self.vector_searches.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment backup_dumps by 1.
    pub fn increment_backup_dumps(&self) {
        self.backup_dumps.fetch_add(1, Ordering::Relaxed);
    }

    /// Add to restore_records (batch restore).
    pub fn add_restore_records(&self, count: u64) {
        self.restore_records.fetch_add(count, Ordering::Relaxed);
    }
}

/// Non-atomic telemetry snapshot.
/// Serializable for UI display or persistence.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DbTelemetrySnapshot {
    /// Total SQL queries executed.
    pub queries_executed: u64,

    /// SQL queries that failed.
    pub queries_failed: u64,

    /// Migrations applied in this session.
    pub migrations_applied: u64,

    /// Vector similarity searches executed.
    pub vector_searches: u64,

    /// Backup dumps written.
    pub backup_dumps: u64,

    /// Records restored from backups.
    pub restore_records: u64,
}

impl DbTelemetrySnapshot {
    /// Success rate as a percentage (0–100). Returns None if no queries attempted.
    pub fn success_rate(&self) -> Option<f64> {
        if self.queries_executed == 0 {
            return None;
        }
        let success = self.queries_executed - self.queries_failed;
        Some((success as f64 / self.queries_executed as f64) * 100.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_telemetry_default_zero() {
        let t = DbTelemetry::default();
        let s = t.snapshot();
        assert_eq!(s.queries_executed, 0);
        assert_eq!(s.queries_failed, 0);
        assert_eq!(s.migrations_applied, 0);
        assert_eq!(s.vector_searches, 0);
        assert_eq!(s.backup_dumps, 0);
        assert_eq!(s.restore_records, 0);
    }

    #[test]
    fn test_increment_queries_executed() {
        let t = DbTelemetry::default();
        t.increment_queries_executed();
        t.increment_queries_executed();
        let s = t.snapshot();
        assert_eq!(s.queries_executed, 2);
    }

    #[test]
    fn test_increment_queries_failed() {
        let t = DbTelemetry::default();
        t.increment_queries_executed();
        t.increment_queries_executed();
        t.increment_queries_failed();
        let s = t.snapshot();
        assert_eq!(s.queries_executed, 2);
        assert_eq!(s.queries_failed, 1);
    }

    #[test]
    fn test_add_restore_records_batch() {
        let t = DbTelemetry::default();
        t.add_restore_records(42);
        t.add_restore_records(8);
        let s = t.snapshot();
        assert_eq!(s.restore_records, 50);
    }

    #[test]
    fn test_success_rate_none_when_zero_queries() {
        let s = DbTelemetrySnapshot {
            queries_executed: 0,
            queries_failed: 0,
            migrations_applied: 0,
            vector_searches: 0,
            backup_dumps: 0,
            restore_records: 0,
        };
        assert_eq!(s.success_rate(), None);
    }

    #[test]
    fn test_success_rate_calculation() {
        let s = DbTelemetrySnapshot {
            queries_executed: 100,
            queries_failed: 10,
            migrations_applied: 0,
            vector_searches: 0,
            backup_dumps: 0,
            restore_records: 0,
        };
        let rate = s.success_rate().expect("success_rate failed");
        assert!((rate - 90.0).abs() < 0.01); // 90%
    }

    #[test]
    fn test_snapshot_is_serializable() {
        let s = DbTelemetrySnapshot {
            queries_executed: 100,
            queries_failed: 5,
            migrations_applied: 2,
            vector_searches: 42,
            backup_dumps: 1,
            restore_records: 33,
        };
        let json = serde_json::to_string(&s).expect("serialization failed");
        let s2: DbTelemetrySnapshot = serde_json::from_str(&json).expect("deserialization failed");
        assert_eq!(s.queries_executed, s2.queries_executed);
    }
}
