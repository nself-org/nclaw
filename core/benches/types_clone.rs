use criterion::{black_box, criterion_group, criterion_main, Criterion};
use libnclaw::types::*;
use uuid::Uuid;
use chrono::Utc;

fn benchmark_message_clone(c: &mut Criterion) {
    let msg = black_box(Message {
        id: Uuid::new_v4(),
        conversation_id: Uuid::new_v4(),
        role: MessageRole::User,
        content: MessageContent::Text("Sample message content".to_string()),
        created_at: Utc::now(),
        model: None,
        tool_calls: vec![],
        metadata: MessageMetadata::default(),
    });

    c.bench_function("message_clone", |b| {
        b.iter(|| {
            let _ = black_box(msg.clone());
        })
    });
}

fn benchmark_memory_clone(c: &mut Criterion) {
    let mem = black_box(Memory {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        topic_id: Some(Uuid::new_v4()),
        content: "Important memory fact".to_string(),
        memory_type: MemoryType::Fact,
        created_at: Utc::now(),
        updated_at: Utc::now(),
        confidence: 0.87,
        sources: vec!["msg_001".to_string(), "msg_002".to_string()],
    });

    c.bench_function("memory_clone", |b| {
        b.iter(|| {
            let _ = black_box(mem.clone());
        })
    });
}

fn benchmark_entity_clone(c: &mut Criterion) {
    let entity = black_box(Entity {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        topic_id: Some(Uuid::new_v4()),
        name: "John Smith".to_string(),
        entity_type: "person".to_string(),
        attributes: serde_json::json!({"company": "Acme", "role": "engineer"}),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        mention_count: 23,
    });

    c.bench_function("entity_clone", |b| {
        b.iter(|| {
            let _ = black_box(entity.clone());
        })
    });
}

fn benchmark_conversation_clone(c: &mut Criterion) {
    let conv = black_box(Conversation {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        title: Some("Q4 Planning".to_string()),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        message_count: 42,
        is_pinned: true,
        branch_parent_id: None,
    });

    c.bench_function("conversation_clone", |b| {
        b.iter(|| {
            let _ = black_box(conv.clone());
        })
    });
}

criterion_group!(benches,
    benchmark_message_clone,
    benchmark_memory_clone,
    benchmark_entity_clone,
    benchmark_conversation_clone
);
criterion_main!(benches);
