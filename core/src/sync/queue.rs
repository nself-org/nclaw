//! Offline event queue.
//!
//! A FIFO queue of pending events ready to be pushed to the server.
//! Persisted via trait (Backup) — implementation deferred to sync client.

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::Mutex;

/// A queued event awaiting upload to the server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueuedEvent {
    pub event_id: uuid::Uuid,
    pub payload: serde_json::Value,
    pub enqueued_at: chrono::DateTime<chrono::Utc>,
    pub attempts: u32,
}

/// Offline queue for pending events.
pub struct OfflineQueue {
    inner: Mutex<VecDeque<QueuedEvent>>,
}

impl OfflineQueue {
    /// Create a new empty queue.
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(VecDeque::new()),
        }
    }

    /// Enqueue an event.
    pub fn enqueue(&self, ev: QueuedEvent) {
        if let Ok(mut q) = self.inner.lock() {
            q.push_back(ev);
        }
    }

    /// Pop up to `n` events from the front of the queue (FIFO).
    pub fn pop_batch(&self, n: usize) -> Vec<QueuedEvent> {
        if let Ok(mut q) = self.inner.lock() {
            (0..n.min(q.len())).filter_map(|_| q.pop_front()).collect()
        } else {
            Vec::new()
        }
    }

    /// Current queue length.
    pub fn len(&self) -> usize {
        self.inner.lock().map(|q| q.len()).unwrap_or(0)
    }

    /// Check if queue is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

impl Default for OfflineQueue {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enqueue_pop_batch_fifo() {
        let q = OfflineQueue::new();
        let ev1 = QueuedEvent {
            event_id: uuid::Uuid::new_v4(),
            payload: serde_json::json!({"msg": "first"}),
            enqueued_at: chrono::Utc::now(),
            attempts: 0,
        };
        let ev2 = QueuedEvent {
            event_id: uuid::Uuid::new_v4(),
            payload: serde_json::json!({"msg": "second"}),
            enqueued_at: chrono::Utc::now(),
            attempts: 0,
        };
        let ev3 = QueuedEvent {
            event_id: uuid::Uuid::new_v4(),
            payload: serde_json::json!({"msg": "third"}),
            enqueued_at: chrono::Utc::now(),
            attempts: 0,
        };

        q.enqueue(ev1.clone());
        q.enqueue(ev2.clone());
        q.enqueue(ev3.clone());

        assert_eq!(q.len(), 3);

        let batch = q.pop_batch(2);
        assert_eq!(batch.len(), 2);
        assert_eq!(batch[0].payload["msg"], "first");
        assert_eq!(batch[1].payload["msg"], "second");

        assert_eq!(q.len(), 1);

        let batch2 = q.pop_batch(10);
        assert_eq!(batch2.len(), 1);
        assert_eq!(batch2[0].payload["msg"], "third");

        assert!(q.is_empty());
    }

    #[test]
    fn pop_batch_empty_queue() {
        let q = OfflineQueue::new();
        let batch = q.pop_batch(5);
        assert!(batch.is_empty());
        assert_eq!(q.len(), 0);
    }
}
