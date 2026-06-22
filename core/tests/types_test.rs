//! Integration tests for libnclaw::types — serialization round-trips.
//!
//! Verifies that all protocol types serialize and deserialize correctly via
//! serde_json, covering Message, ContentPart, Memory, and Entity.

use libnclaw::types::{
    ContentPart, Entity, Memory, MemoryType, Message, MessageContent, MessageMetadata,
    MessageRole,
};
use chrono::Utc;
use uuid::Uuid;

#[test]
fn test_message_serialization_roundtrip() {
    let msg = Message {
        id: Uuid::new_v4(),
        conversation_id: Uuid::new_v4(),
        role: MessageRole::Assistant,
        content: MessageContent::Text("Hello".to_string()),
        created_at: Utc::now(),
        model: Some("claude-3".to_string()),
        tool_calls: vec![],
        metadata: MessageMetadata {
            input_tokens: Some(100),
            output_tokens: Some(50),
            first_token_ms: Some(250),
            from_cache: false,
        },
    };
    let json = serde_json::to_string(&msg).expect("serialize");
    let parsed: Message = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(parsed.id, msg.id);
    assert_eq!(parsed.role, MessageRole::Assistant);
}

#[test]
fn test_content_part_serialization() {
    let part = ContentPart::Image {
        url: "https://example.com/img.png".to_string(),
        mime_type: "image/png".to_string(),
    };
    let json = serde_json::to_string(&part).expect("serialize");
    assert!(json.contains("image"));
    let parsed: ContentPart = serde_json::from_str(&json).expect("deserialize");
    if let ContentPart::Image { url, .. } = parsed {
        assert_eq!(url, "https://example.com/img.png");
    }
}

#[test]
fn test_memory_serialization() {
    let mem = Memory {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        topic_id: Some(Uuid::new_v4()),
        content: "User prefers dark mode".to_string(),
        memory_type: MemoryType::Preference,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        confidence: 0.95,
        sources: vec!["msg_123".to_string()],
    };
    let json = serde_json::to_string(&mem).expect("serialize");
    let parsed: Memory = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(parsed.memory_type, MemoryType::Preference);
    assert!(parsed.confidence > 0.9);
}

#[test]
fn test_entity_serialization() {
    let ent = Entity {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        topic_id: None,
        name: "Alice".to_string(),
        entity_type: "person".to_string(),
        attributes: serde_json::json!({"role": "friend"}),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        mention_count: 5,
    };
    let json = serde_json::to_string(&ent).expect("serialize");
    let parsed: Entity = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(parsed.name, "Alice");
    assert_eq!(parsed.mention_count, 5);
}
