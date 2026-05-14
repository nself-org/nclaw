//! Last-Write-Wins resolution per nclaw/protocol/sync-protocol.md §4.
//!
//! Implements deterministic conflict resolution for concurrent edits across
//! devices using HLC timestamps. Delete operations create tombstones that
//! supersede earlier updates.

use crate::sync::hlc::Hlc;
use serde::{Deserialize, Serialize};

/// Event operation type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Op {
    Insert,
    Update,
    Delete,
}

/// Canonical event envelope with HLC timestamp and cryptographic signature.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventEnvelope {
    pub event_id: uuid::Uuid,
    pub entity_type: String,
    pub entity_id: uuid::Uuid,
    pub op: Op,
    pub timestamp: Hlc,
    pub user_id: uuid::Uuid,
    pub device_id: uuid::Uuid,
    pub tenant_id: Option<uuid::Uuid>,
    pub payload: Option<serde_json::Value>,
    pub schema_version: u32,
    pub signature: Vec<u8>,
}

/// Resolve a stream of events for the same (entity_type, entity_id) → return winning state.
///
/// Algorithm:
/// 1. Sort events by HLC total order (wall_ms → lamport → device_id).
/// 2. Iterate forward; track the most recent non-deleted event.
/// 3. Once a Delete arrives, all earlier events are tombstoned.
/// 4. Return the final event state (Insert/Update if alive, Delete if tombstoned).
pub fn resolve(events: &[EventEnvelope]) -> Option<EventEnvelope> {
    if events.is_empty() {
        return None;
    }

    // Sort by HLC (timestamp ordering: wall → lamport → device_id).
    let mut sorted = events.to_vec();
    sorted.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

    // Once a Delete arrives, tombstone wins for all events older than the delete.
    // Iterate; skip events older than any seen Delete.
    let mut current: Option<EventEnvelope> = None;
    let mut delete_at: Option<Hlc> = None;

    for ev in sorted {
        // If we've seen a delete and this event is older, skip it.
        if let Some(d) = delete_at {
            if ev.timestamp <= d {
                continue;
            }
        }
        match ev.op {
            Op::Delete => {
                delete_at = Some(ev.timestamp);
                current = Some(ev);
            }
            _ => current = Some(ev),
        }
    }
    current
}

/// Per-field LWW merge for two update events.
///
/// When two clients edit different fields of the same entity, merge their updates
/// by taking the newest value per field (by HLC).
/// Returns merged JSON object; for each key, latest timestamp wins.
pub fn merge_field_updates(a: &EventEnvelope, b: &EventEnvelope) -> serde_json::Value {
    let (older, newer) = if a.timestamp <= b.timestamp {
        (a, b)
    } else {
        (b, a)
    };

    let mut merged = older
        .payload
        .clone()
        .unwrap_or_else(|| serde_json::json!({}));

    if let (Some(m), Some(n)) = (
        merged.as_object_mut(),
        newer.payload.as_ref().and_then(|p| p.as_object()),
    ) {
        for (k, v) in n {
            m.insert(k.clone(), v.clone());
        }
    }

    merged
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_event(
        event_id: uuid::Uuid,
        op: Op,
        wall_ms: i64,
        lamport: u64,
        device_id: uuid::Uuid,
        payload: Option<serde_json::Value>,
    ) -> EventEnvelope {
        EventEnvelope {
            event_id,
            entity_type: "test".to_string(),
            entity_id: uuid::Uuid::new_v4(),
            op,
            timestamp: Hlc {
                wall_ms,
                lamport,
                device_id,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id,
            tenant_id: None,
            payload,
            schema_version: 1,
            signature: vec![],
        }
    }

    #[test]
    fn resolve_empty_returns_none() {
        assert_eq!(resolve(&[]), None);
    }

    #[test]
    fn resolve_single_event_returns_that_event() {
        let dev = uuid::Uuid::new_v4();
        let ev = make_event(
            uuid::Uuid::new_v4(),
            Op::Insert,
            1000,
            0,
            dev,
            Some(serde_json::json!({"name": "Alice"})),
        );
        let result = resolve(&[ev.clone()]);
        assert!(result.is_some());
        assert_eq!(result.unwrap().event_id, ev.event_id);
    }

    #[test]
    fn resolve_insert_then_update_returns_update() {
        let dev = uuid::Uuid::new_v4();
        let id = uuid::Uuid::new_v4();
        let ev1 = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Insert,
            timestamp: Hlc {
                wall_ms: 1000,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: Some(serde_json::json!({"name": "Alice"})),
            schema_version: 1,
            signature: vec![],
        };
        let ev2 = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Update,
            timestamp: Hlc {
                wall_ms: 2000,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: Some(serde_json::json!({"name": "Bob"})),
            schema_version: 1,
            signature: vec![],
        };
        let result = resolve(&[ev1, ev2.clone()]);
        assert_eq!(result.unwrap().event_id, ev2.event_id);
    }

    #[test]
    fn resolve_delete_tombstones_earlier_updates() {
        let dev = uuid::Uuid::new_v4();
        let id = uuid::Uuid::new_v4();
        let ev_insert = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Insert,
            timestamp: Hlc {
                wall_ms: 1000,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: Some(serde_json::json!({})),
            schema_version: 1,
            signature: vec![],
        };
        let ev_update = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Update,
            timestamp: Hlc {
                wall_ms: 1500,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: Some(serde_json::json!({})),
            schema_version: 1,
            signature: vec![],
        };
        let ev_delete = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Delete,
            timestamp: Hlc {
                wall_ms: 2000,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: None,
            schema_version: 1,
            signature: vec![],
        };
        let result = resolve(&[ev_insert, ev_update, ev_delete.clone()]);
        assert_eq!(result.unwrap().op, Op::Delete);
    }

    #[test]
    fn resolve_insert_after_delete_wins() {
        let dev = uuid::Uuid::new_v4();
        let id = uuid::Uuid::new_v4();
        let ev_delete = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Delete,
            timestamp: Hlc {
                wall_ms: 2000,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: None,
            schema_version: 1,
            signature: vec![],
        };
        let ev_insert = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: id,
            op: Op::Insert,
            timestamp: Hlc {
                wall_ms: 3000,
                lamport: 0,
                device_id: dev,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev,
            tenant_id: None,
            payload: Some(serde_json::json!({})),
            schema_version: 1,
            signature: vec![],
        };
        let result = resolve(&[ev_delete, ev_insert.clone()]);
        assert_eq!(result.unwrap().op, Op::Insert);
    }

    #[test]
    fn merge_field_updates_takes_newest_per_field() {
        let dev_a = uuid::Uuid::new_v4();
        let ev_a = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: uuid::Uuid::new_v4(),
            op: Op::Update,
            timestamp: Hlc {
                wall_ms: 1000,
                lamport: 0,
                device_id: dev_a,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev_a,
            tenant_id: None,
            payload: Some(serde_json::json!({"name": "Alice", "age": 30})),
            schema_version: 1,
            signature: vec![],
        };
        let dev_b = uuid::Uuid::new_v4();
        let ev_b = EventEnvelope {
            event_id: uuid::Uuid::new_v4(),
            entity_type: "test".to_string(),
            entity_id: uuid::Uuid::new_v4(),
            op: Op::Update,
            timestamp: Hlc {
                wall_ms: 2000,
                lamport: 0,
                device_id: dev_b,
            },
            user_id: uuid::Uuid::new_v4(),
            device_id: dev_b,
            tenant_id: None,
            payload: Some(serde_json::json!({"name": "Bob", "city": "NYC"})),
            schema_version: 1,
            signature: vec![],
        };
        let merged = merge_field_updates(&ev_a, &ev_b);
        assert_eq!(merged.get("name").and_then(|v| v.as_str()), Some("Bob"));
        assert_eq!(merged.get("age").and_then(|v| v.as_i64()), Some(30));
        assert_eq!(merged.get("city").and_then(|v| v.as_str()), Some("NYC"));
    }
}
