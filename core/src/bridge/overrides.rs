//! Per-conversation routing overrides.
//!
//! S19.T05: Allows users to pin a specific route for an entire conversation
//! (e.g., "always use local", "always use ServerMux"). Overrides are stored
//! and persisted via a simple in-memory RwLock-backed store.

use crate::bridge::router::RouteOverride;
use std::collections::HashMap;
use std::sync::RwLock;

/// Recover a poisoned RwLock write guard, logging a warning.
///
/// A lock is poisoned when a thread panics while holding it. Recovery via
/// `into_inner()` extracts the data regardless — the HashMap state is intact
/// because HashMap operations do not leave partially-written state observable
/// to other threads. This is safe for routing overrides (in-memory cache).
macro_rules! write_lock {
    ($lock:expr) => {
        $lock.write().unwrap_or_else(|poisoned| {
            tracing::warn!(
                "OverridesStore: RwLock write-guard was poisoned; \
                 recovering data (in-memory routing overrides may be stale)"
            );
            poisoned.into_inner()
        })
    };
}

/// Recover a poisoned RwLock read guard, logging a warning.
macro_rules! read_lock {
    ($lock:expr) => {
        $lock.read().unwrap_or_else(|poisoned| {
            tracing::warn!(
                "OverridesStore: RwLock read-guard was poisoned; \
                 recovering data (in-memory routing overrides may be stale)"
            );
            poisoned.into_inner()
        })
    };
}

/// Thread-safe store for per-conversation routing overrides.
///
/// Internally uses a `HashMap<conversation_id, RouteOverride>` protected by
/// a `RwLock`. Reads are cheap; writes acquire exclusive lock.
pub struct OverridesStore {
    inner: RwLock<HashMap<String, RouteOverride>>,
}

impl OverridesStore {
    /// Create a new empty overrides store.
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(HashMap::new()),
        }
    }

    /// Set an override for a conversation. Overwrites any prior override.
    pub fn set(&self, conversation_id: impl Into<String>, override_: RouteOverride) {
        let cid = conversation_id.into();
        write_lock!(self.inner).insert(cid, override_);
    }

    /// Get the override for a conversation, if set. Returns `None` if no override.
    pub fn get(&self, conversation_id: &str) -> Option<RouteOverride> {
        read_lock!(self.inner).get(conversation_id).cloned()
    }

    /// Clear the override for a conversation.
    pub fn clear(&self, conversation_id: &str) {
        write_lock!(self.inner).remove(conversation_id);
    }

    /// Get the number of active overrides.
    pub fn count(&self) -> usize {
        read_lock!(self.inner).len()
    }

    /// Clear all overrides.
    pub fn clear_all(&self) {
        write_lock!(self.inner).clear();
    }

    /// List all conversations with active overrides.
    pub fn list_conversations(&self) -> Vec<String> {
        read_lock!(self.inner).keys().cloned().collect()
    }
}

impl Default for OverridesStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overrides_store_set_and_get() {
        let store = OverridesStore::new();
        let ovr = RouteOverride::ForceLocal;
        store.set("conv1", ovr.clone());
        assert_eq!(store.get("conv1"), Some(ovr));
    }

    #[test]
    fn overrides_store_clear() {
        let store = OverridesStore::new();
        store.set("conv1", RouteOverride::ForceLocal);
        assert!(store.get("conv1").is_some());
        store.clear("conv1");
        assert!(store.get("conv1").is_none());
    }

    #[test]
    fn overrides_store_count() {
        let store = OverridesStore::new();
        store.set("conv1", RouteOverride::ForceLocal);
        store.set("conv2", RouteOverride::ForceServerMux);
        assert_eq!(store.count(), 2);
        store.clear("conv1");
        assert_eq!(store.count(), 1);
    }

    #[test]
    fn overrides_store_list() {
        let store = OverridesStore::new();
        store.set("conv1", RouteOverride::ForceLocal);
        store.set("conv2", RouteOverride::ForceServerMux);
        let convs = store.list_conversations();
        assert!(convs.contains(&"conv1".to_string()));
        assert!(convs.contains(&"conv2".to_string()));
    }

    #[test]
    fn overrides_store_default() {
        let store = OverridesStore::default();
        assert_eq!(store.count(), 0);
    }
}
