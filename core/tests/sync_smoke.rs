//! Smoke tests for sync module: HLC, queue, and client state machine.

use libnclaw::sync::{HlcGenerator, OfflineQueue, QueuedEvent, SyncClient, SyncState};
use uuid::Uuid;

#[test]
fn hlc_generator_tick_monotonic() {
    let gen = HlcGenerator::new(Uuid::nil());
    let h1 = gen.tick();
    let h2 = gen.tick();
    let h3 = gen.tick();

    assert!(h1 < h2, "ticks should be monotonically increasing");
    assert!(h2 < h3, "consecutive ticks should be strictly ordered");
}

#[test]
fn hlc_merge_advances_state() {
    let gen = HlcGenerator::new(Uuid::nil());
    let other_device = Uuid::new_v4();

    let incoming = libnclaw::sync::Hlc {
        wall_ms: 5000,
        lamport: 10,
        device_id: other_device,
    };

    let merged = gen.merge(&incoming);

    // After merge, local HLC should be >= incoming HLC
    assert!(merged >= incoming, "merged HLC must be >= incoming");
}

#[test]
fn offline_queue_fifo_order() {
    let queue = OfflineQueue::new();

    let ev1 = QueuedEvent {
        event_id: Uuid::new_v4(),
        payload: serde_json::json!({"i": 1}),
        enqueued_at: chrono::Utc::now(),
        attempts: 0,
    };
    let ev2 = QueuedEvent {
        event_id: Uuid::new_v4(),
        payload: serde_json::json!({"i": 2}),
        enqueued_at: chrono::Utc::now(),
        attempts: 0,
    };
    let ev3 = QueuedEvent {
        event_id: Uuid::new_v4(),
        payload: serde_json::json!({"i": 3}),
        enqueued_at: chrono::Utc::now(),
        attempts: 0,
    };

    queue.enqueue(ev1.clone());
    queue.enqueue(ev2.clone());
    queue.enqueue(ev3.clone());

    assert_eq!(queue.len(), 3);

    let batch = queue.pop_batch(2);
    assert_eq!(batch.len(), 2);
    assert_eq!(batch[0].payload["i"], 1, "first event should be first out");
    assert_eq!(
        batch[1].payload["i"], 2,
        "second event should be second out"
    );

    assert_eq!(queue.len(), 1);

    let batch2 = queue.pop_batch(10);
    assert_eq!(batch2.len(), 1);
    assert_eq!(batch2[0].payload["i"], 3, "third event should be last out");

    assert!(queue.is_empty());
}

#[test]
fn sync_client_state_machine() {
    let client = SyncClient::new("http://localhost:8080", Uuid::new_v4());

    assert_eq!(client.state(), SyncState::Disconnected);

    client.set_state(SyncState::Connecting);
    assert_eq!(client.state(), SyncState::Connecting);

    client.set_state(SyncState::Connected);
    assert_eq!(client.state(), SyncState::Connected);

    client.set_state(SyncState::Syncing);
    assert_eq!(client.state(), SyncState::Syncing);

    client.set_state(SyncState::Idle);
    assert_eq!(client.state(), SyncState::Idle);

    client.set_state(SyncState::Disconnected);
    assert_eq!(client.state(), SyncState::Disconnected);
}

#[test]
fn sync_client_push_stub_empty_queue() {
    let client = SyncClient::new("http://localhost:8080", Uuid::new_v4());
    let count = client.push_stub();

    assert_eq!(count, 0, "push_stub on empty queue should return 0");
}

#[test]
fn hlc_total_order_property() {
    let dev_a = Uuid::new_v4();
    let dev_b = Uuid::new_v4();
    let (dev_early, dev_late) = if dev_a < dev_b {
        (dev_a, dev_b)
    } else {
        (dev_b, dev_a)
    };

    let h_early_wall = libnclaw::sync::Hlc {
        wall_ms: 1000,
        lamport: 0,
        device_id: dev_early,
    };
    let h_later_wall = libnclaw::sync::Hlc {
        wall_ms: 2000,
        lamport: 0,
        device_id: dev_early,
    };
    let h_same_wall_early_dev = libnclaw::sync::Hlc {
        wall_ms: 1000,
        lamport: 0,
        device_id: dev_early,
    };
    let h_same_wall_late_dev = libnclaw::sync::Hlc {
        wall_ms: 1000,
        lamport: 0,
        device_id: dev_late,
    };

    assert!(
        h_early_wall < h_later_wall,
        "earlier wall_ms should come first"
    );
    assert!(
        h_same_wall_early_dev < h_same_wall_late_dev,
        "same wall/lamport: lexicographic device_id ties"
    );
}
