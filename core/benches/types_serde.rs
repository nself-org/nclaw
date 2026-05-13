use criterion::{black_box, criterion_group, criterion_main, Criterion};
use libnclaw::types::*;
use uuid::Uuid;
use chrono::Utc;

fn benchmark_message_roundtrip(c: &mut Criterion) {
    c.bench_function("message_serialize_deserialize", |b| {
        b.iter(|| {
            let msg = black_box(Message {
                id: Uuid::new_v4(),
                conversation_id: Uuid::new_v4(),
                role: MessageRole::Assistant,
                content: MessageContent::Text("Hello world".to_string()),
                created_at: Utc::now(),
                model: Some("claude-3".to_string()),
                tool_calls: vec![],
                metadata: MessageMetadata {
                    input_tokens: Some(100),
                    output_tokens: Some(50),
                    first_token_ms: Some(250),
                    from_cache: false,
                },
            });
            let json = serde_json::to_string(&msg).unwrap();
            let _parsed: Message = serde_json::from_str(&json).unwrap();
        })
    });
}

fn benchmark_memory_roundtrip(c: &mut Criterion) {
    c.bench_function("memory_serialize_deserialize", |b| {
        b.iter(|| {
            let mem = black_box(Memory {
                id: Uuid::new_v4(),
                user_id: Uuid::new_v4(),
                topic_id: Some(Uuid::new_v4()),
                content: "User prefers dark mode".to_string(),
                memory_type: MemoryType::Preference,
                created_at: Utc::now(),
                updated_at: Utc::now(),
                confidence: 0.95,
                sources: vec!["msg_123".to_string()],
            });
            let json = serde_json::to_string(&mem).unwrap();
            let _parsed: Memory = serde_json::from_str(&json).unwrap();
        })
    });
}

fn benchmark_topic_roundtrip(c: &mut Criterion) {
    c.bench_function("topic_serialize_deserialize", |b| {
        b.iter(|| {
            let topic = black_box(Topic {
                id: Uuid::new_v4(),
                user_id: Uuid::new_v4(),
                title: "Work Projects".to_string(),
                description: Some("All my professional work".to_string()),
                created_at: Utc::now(),
                updated_at: Utc::now(),
                entity_count: 42,
                conversation_count: 157,
            });
            let json = serde_json::to_string(&topic).unwrap();
            let _parsed: Topic = serde_json::from_str(&json).unwrap();
        })
    });
}

criterion_group!(benches,
    benchmark_message_roundtrip,
    benchmark_memory_roundtrip,
    benchmark_topic_roundtrip
);
criterion_main!(benches);
