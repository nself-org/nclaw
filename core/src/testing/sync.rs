//! `InMemorySync` — no-op sync engine for testing.
//!
//! Records all method calls without side effects. Use `get_calls()` to assert
//! which sync operations were invoked during a test.

use crate::backend::*;
use crate::error::*;
use std::result::Result;
use std::sync::{Arc, Mutex};

/// No-op sync engine — records calls, simulates sync without side effects.
pub struct InMemorySync {
    calls: Arc<Mutex<Vec<String>>>,
}

impl InMemorySync {
    /// Create a builder for `InMemorySync`.
    pub fn builder() -> InMemorySyncBuilder {
        InMemorySyncBuilder { calls: Vec::new() }
    }

    /// Return a snapshot of all recorded sync-method call strings.
    pub fn get_calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }
}

/// Builder for `InMemorySync` — no configurable options, exists for API symmetry.
pub struct InMemorySyncBuilder {
    calls: Vec<String>,
}

impl InMemorySyncBuilder {
    /// Build the `InMemorySync` instance.
    pub fn build(self) -> InMemorySync {
        InMemorySync {
            calls: Arc::new(Mutex::new(self.calls)),
        }
    }
}

#[async_trait::async_trait]
impl SyncEngine for InMemorySync {
    async fn push(&self, changes: &[Change]) -> Result<Vec<Conflict>, SyncError> {
        let mut calls = self.calls.lock().unwrap();
        calls.push(format!("push({} changes)", changes.len()));
        Ok(Vec::new())
    }

    async fn pull(&self) -> Result<Vec<Change>, SyncError> {
        let mut calls = self.calls.lock().unwrap();
        calls.push("pull".into());
        Ok(Vec::new())
    }

    async fn sync(&self) -> Result<SyncState, SyncError> {
        let mut calls = self.calls.lock().unwrap();
        calls.push("sync".into());
        Ok(SyncState {
            synced_count: 0,
            conflicts_resolved: 0,
            next_sync_version: 1,
        })
    }

    async fn resolve_conflict(
        &self,
        _conflict: &Conflict,
        _strategy: MergeStrategy,
    ) -> Result<(), SyncError> {
        Ok(())
    }
}
