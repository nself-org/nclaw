//! Integration tests for libnclaw::llm::context — ContextManager truncation policies.
//!
//! Uses only public API: `ContextManager`, `TruncationPolicy`.

use libnclaw::llm::context::{ContextManager, TruncationPolicy};
use libnclaw::types::{Message, MessageContent, MessageMetadata, MessageRole};

fn make_msg(conv_id: uuid::Uuid, role: MessageRole, text: &str) -> Message {
    Message {
        id: uuid::Uuid::new_v4(),
        conversation_id: conv_id,
        role,
        content: MessageContent::Text(text.to_string()),
        created_at: chrono::Utc::now(),
        model: None,
        tool_calls: vec![],
        metadata: MessageMetadata::default(),
    }
}

#[test]
fn test_empty_input() {
    let mgr = ContextManager::default();
    let fitted = mgr.fit(&[], 10000);
    assert_eq!(fitted.len(), 0);
}

#[test]
fn test_all_messages_fit() {
    let conv_id = uuid::Uuid::new_v4();
    let mut messages = vec![];

    for i in 0..5 {
        let role = if i % 2 == 0 { MessageRole::User } else { MessageRole::Assistant };
        messages.push(make_msg(conv_id, role, "short"));
    }

    let mgr = ContextManager::default();
    let fitted = mgr.fit(&messages, 10000);
    assert_eq!(fitted.len(), 5);
}

#[test]
fn test_keep_recent_policy() {
    let conv_id = uuid::Uuid::new_v4();
    let messages: Vec<_> = (0..10)
        .map(|_| make_msg(conv_id, MessageRole::User, "This is a message with some text content."))
        .collect();

    let mgr = ContextManager { policy: TruncationPolicy::KeepRecent, recent_keep: 8 };

    // Budget 50 so KeepRecent drops oldest messages.
    let fitted = mgr.fit(&messages, 50);

    assert!(fitted.len() < messages.len());
    assert_eq!(fitted.last().map(|m| &m.id), messages.last().map(|m| &m.id));
}

#[test]
fn test_summarize_middle_policy() {
    let conv_id = uuid::Uuid::new_v4();
    let mut messages = vec![make_msg(conv_id, MessageRole::System, "You are a helpful assistant.")];

    for i in 0..20 {
        let role = if i % 2 == 0 { MessageRole::User } else { MessageRole::Assistant };
        messages.push(make_msg(conv_id, role, "This is a message with some text content."));
    }

    let mgr = ContextManager { policy: TruncationPolicy::SummarizeMiddle, recent_keep: 8 };

    // Budget 150 so SummarizeMiddle truncates and inserts placeholder.
    let fitted = mgr.fit(&messages, 150);

    assert!(fitted.len() > 1);
    assert!(fitted.len() <= 10); // system + placeholder + 8 recent max
    assert_eq!(fitted.first().map(|m| &m.role), Some(&MessageRole::System));

    let has_summary = fitted.iter().any(|m| {
        m.role == MessageRole::System
            && m.content.as_text().is_some_and(|t| t.contains("earlier messages"))
    });
    assert!(has_summary);
    assert_eq!(fitted.last().map(|m| &m.id), messages.last().map(|m| &m.id));
}

#[test]
fn test_system_messages_always_preserved() {
    let conv_id = uuid::Uuid::new_v4();
    let mut messages: Vec<_> = (0..3)
        .map(|i| make_msg(conv_id, MessageRole::System, &format!("System message {}", i)))
        .collect();

    for _ in 0..20 {
        messages.push(make_msg(conv_id, MessageRole::User, "User message with some text content here."));
    }

    let mgr = ContextManager { policy: TruncationPolicy::KeepRecent, recent_keep: 8 };
    let fitted = mgr.fit(&messages, 200);

    let system_count = fitted.iter().filter(|m| m.role == MessageRole::System).count();
    assert_eq!(system_count, 3);

    for msg in fitted.iter().take(3) {
        assert_eq!(msg.role, MessageRole::System);
    }
}

#[test]
fn test_truncate_oldest_alias() {
    let conv_id = uuid::Uuid::new_v4();
    let messages: Vec<_> = (0..10)
        .map(|_| make_msg(conv_id, MessageRole::User, "Message with content here."))
        .collect();

    let mgr_keep = ContextManager { policy: TruncationPolicy::KeepRecent, recent_keep: 8 };
    let mgr_trunc = ContextManager { policy: TruncationPolicy::TruncateOldest, recent_keep: 8 };

    let fitted_keep = mgr_keep.fit(&messages, 300);
    let fitted_trunc = mgr_trunc.fit(&messages, 300);

    assert_eq!(fitted_keep.len(), fitted_trunc.len());
    assert_eq!(
        fitted_keep.iter().map(|m| m.id).collect::<Vec<_>>(),
        fitted_trunc.iter().map(|m| m.id).collect::<Vec<_>>()
    );
}

