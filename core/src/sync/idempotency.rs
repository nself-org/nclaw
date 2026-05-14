//! Idempotency cache for duplicate event detection.
//!
//! Tracks event IDs recently seen to prevent processing the same event twice.
//! Uses an LRU eviction policy with a bounded size (default 10,000 most-recent IDs).

use std::collections::VecDeque;
use uuid::Uuid;

/// Idempotency cache — deduplicates events by ID.
#[derive(Debug, Clone)]
pub struct IdempotencyCache {
    /// Bounded set of recent event IDs; older entries are evicted FIFO.
    cache: VecDeque<Uuid>,
    /// Maximum number of event IDs to track.
    max_size: usize,
}

impl Default for IdempotencyCache {
    fn default() -> Self {
        Self::new(10000)
    }
}

impl IdempotencyCache {
    /// Create a new idempotency cache with max size.
    pub fn new(max_size: usize) -> Self {
        Self {
            cache: VecDeque::with_capacity(max_size),
            max_size,
        }
    }

    /// Check if an event ID is in the cache. If new, insert it. Return true if new, false if duplicate.
    ///
    /// When the cache is full, the oldest entry (FIFO) is evicted before inserting the new one.
    pub fn check_and_insert(&mut self, event_id: Uuid) -> bool {
        if self.cache.contains(&event_id) {
            return false; // Duplicate
        }

        // Cache miss; this is a new event.
        if self.cache.len() >= self.max_size {
            self.cache.pop_front(); // Evict oldest
        }
        self.cache.push_back(event_id);
        true // New event
    }

    /// Get the current cache size.
    pub fn len(&self) -> usize {
        self.cache.len()
    }

    /// Check if the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.cache.is_empty()
    }

    /// Clear all entries.
    pub fn clear(&mut self) {
        self.cache.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_event_returns_true() {
        let mut cache = IdempotencyCache::new(100);
        let id = Uuid::new_v4();
        assert!(cache.check_and_insert(id));
    }

    #[test]
    fn duplicate_event_returns_false() {
        let mut cache = IdempotencyCache::new(100);
        let id = Uuid::new_v4();
        assert!(cache.check_and_insert(id));
        assert!(!cache.check_and_insert(id)); // Same ID again
    }

    #[test]
    fn cache_respects_max_size() {
        let mut cache = IdempotencyCache::new(3);
        let id1 = Uuid::new_v4();
        let id2 = Uuid::new_v4();
        let id3 = Uuid::new_v4();
        let id4 = Uuid::new_v4();

        assert!(cache.check_and_insert(id1)); // size = 1
        assert!(cache.check_and_insert(id2)); // size = 2
        assert!(cache.check_and_insert(id3)); // size = 3
        assert!(cache.check_and_insert(id4)); // size = 3; id1 evicted

        assert_eq!(cache.len(), 3);
        assert!(!cache.cache.contains(&id1)); // id1 evicted
        assert!(cache.cache.contains(&id2));
        assert!(cache.cache.contains(&id3));
        assert!(cache.cache.contains(&id4));
    }

    #[test]
    fn clear_empties_cache() {
        let mut cache = IdempotencyCache::new(100);
        let id = Uuid::new_v4();
        cache.check_and_insert(id);
        cache.clear();
        assert!(cache.is_empty());
    }
}
