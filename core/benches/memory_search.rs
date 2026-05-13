use criterion::{black_box, criterion_group, criterion_main, Criterion};
use libnclaw::types::*;
use uuid::Uuid;
use chrono::Utc;

/// Mock in-memory database for memory search benchmarks.
struct InMemoryDb {
    memories: Vec<Memory>,
}

impl InMemoryDb {
    fn new() -> Self {
        Self { memories: Vec::new() }
    }

    fn insert(&mut self, memory: Memory) {
        self.memories.push(memory);
    }

    fn search_by_content(&self, query: &str) -> Vec<&Memory> {
        self.memories
            .iter()
            .filter(|m| m.content.to_lowercase().contains(&query.to_lowercase()))
            .collect()
    }

    fn search_by_type(&self, memory_type: MemoryType) -> Vec<&Memory> {
        self.memories.iter().filter(|m| m.memory_type == memory_type).collect()
    }

    fn search_by_confidence(&self, min: f32) -> Vec<&Memory> {
        self.memories.iter().filter(|m| m.confidence >= min).collect()
    }
}

fn benchmark_memory_search_by_content(c: &mut Criterion) {
    let mut db = InMemoryDb::new();
    for i in 0..1000 {
        db.insert(Memory {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            topic_id: if i % 3 == 0 { Some(Uuid::new_v4()) } else { None },
            content: format!("Memory fact number {} about the user", i),
            memory_type: match i % 6 {
                0 => MemoryType::Fact,
                1 => MemoryType::Preference,
                2 => MemoryType::Goal,
                3 => MemoryType::Event,
                4 => MemoryType::Relationship,
                _ => MemoryType::Rule,
            },
            created_at: Utc::now(),
            updated_at: Utc::now(),
            confidence: (i as f32 % 100.0) / 100.0,
            sources: vec![format!("msg_{}", i)],
        });
    }

    c.bench_function("search_memories_by_content_1000", |b| {
        b.iter(|| {
            let _ = black_box(db.search_by_content("user"));
        })
    });
}

fn benchmark_memory_search_by_type(c: &mut Criterion) {
    let mut db = InMemoryDb::new();
    for i in 0..1000 {
        db.insert(Memory {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            topic_id: None,
            content: format!("Memory {}", i),
            memory_type: if i % 2 == 0 {
                MemoryType::Preference
            } else {
                MemoryType::Fact
            },
            created_at: Utc::now(),
            updated_at: Utc::now(),
            confidence: 0.9,
            sources: vec![],
        });
    }

    c.bench_function("search_memories_by_type_1000", |b| {
        b.iter(|| {
            let _ = black_box(db.search_by_type(MemoryType::Preference));
        })
    });
}

fn benchmark_memory_search_by_confidence(c: &mut Criterion) {
    let mut db = InMemoryDb::new();
    for i in 0..1000 {
        db.insert(Memory {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            topic_id: None,
            content: format!("Memory {}", i),
            memory_type: MemoryType::Fact,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            confidence: (i as f32 % 100.0) / 100.0,
            sources: vec![],
        });
    }

    c.bench_function("search_memories_by_confidence_1000", |b| {
        b.iter(|| {
            let _ = black_box(db.search_by_confidence(0.75));
        })
    });
}

criterion_group!(benches,
    benchmark_memory_search_by_content,
    benchmark_memory_search_by_type,
    benchmark_memory_search_by_confidence
);
criterion_main!(benches);
