use chrono::Utc;
/// Integration tests for context window truncation policies.
///
/// Tests cover all truncation policies, boundary conditions, and system message preservation.
use nclaw_core::llm::context::{ContextManager, TruncationPolicy};
use nclaw_core::types::{Message, MessageContent, MessageMetadata, MessageRole};
use uuid::Uuid;

/// Helper to create a message with given role and content.
fn make_message(conversation_id: Uuid, role: MessageRole, content: &str) -> Message {
    Message {
        id: Uuid::new_v4(),
        conversation_id,
        role,
        content: MessageContent::Text(content.to_string()),
        created_at: Utc::now(),
        model: None,
        tool_calls: vec![],
        metadata: MessageMetadata::default(),
    }
}

#[test]
fn test_fit_empty_input() {
    let mgr = ContextManager::default();
    let fitted = mgr.fit(&[], 10000);
    assert_eq!(fitted.len(), 0, "Empty input should return empty output");
}

#[test]
fn test_fit_all_messages_fit() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    for i in 0..5 {
        let role = if i % 2 == 0 {
            MessageRole::User
        } else {
            MessageRole::Assistant
        };
        messages.push(make_message(conv_id, role, "short"));
    }

    let mgr = ContextManager::default();
    let fitted = mgr.fit(&messages, 10000);

    assert_eq!(fitted.len(), 5, "All messages should fit when under budget");
}

#[test]
fn test_fit_with_tight_budget() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    // Add 20 messages, each ~100 chars
    for i in 0..20 {
        let role = if i % 2 == 0 {
            MessageRole::User
        } else {
            MessageRole::Assistant
        };
        messages.push(make_message(
            conv_id,
            role,
            "This is a message with some text content in it.",
        ));
    }

    let mgr = ContextManager {
        policy: TruncationPolicy::KeepRecent,
        recent_keep: 8,
    };

    let fitted = mgr.fit(&messages, 300);

    // With tight budget, should keep only some recent messages
    assert!(
        fitted.len() < messages.len(),
        "Should drop messages to fit budget"
    );
    assert!(fitted.len() > 0, "Should keep at least some messages");
}

#[test]
fn test_summarize_middle_policy() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    // Add system message
    messages.push(make_message(
        conv_id,
        MessageRole::System,
        "You are a helpful assistant.",
    ));

    // Add 20 body messages
    for i in 0..20 {
        let role = if i % 2 == 0 {
            MessageRole::User
        } else {
            MessageRole::Assistant
        };
        messages.push(make_message(
            conv_id,
            role,
            "This is a message with some text content here.",
        ));
    }

    let mgr = ContextManager {
        policy: TruncationPolicy::SummarizeMiddle,
        recent_keep: 8,
    };

    let fitted = mgr.fit(&messages, 400);

    // Should have system + placeholder + recent messages (max ~10 total)
    assert!(
        fitted.len() <= 12,
        "SummarizeMiddle should keep system + placeholder + ~8 recent"
    );
    assert!(
        fitted.len() > 1,
        "Should have at least system + placeholder"
    );

    // First message should be system
    assert_eq!(
        fitted.first().map(|m| &m.role),
        Some(&MessageRole::System),
        "First message should be system"
    );

    // Should have a summary placeholder
    let has_summary = fitted.iter().any(|m| {
        m.role == MessageRole::System
            && m.content
                .as_text()
                .map_or(false, |t| t.contains("earlier messages"))
    });
    assert!(has_summary, "Should have summary placeholder");

    // Last message should be from original body (recent)
    assert_eq!(
        fitted.last().map(|m| &m.id),
        messages.last().map(|m| &m.id),
        "Last message should be the most recent from original"
    );
}

#[test]
fn test_keep_recent_policy() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    for i in 0..10 {
        messages.push(make_message(
            conv_id,
            MessageRole::User,
            "This is a message with some text content.",
        ));
    }

    let mgr = ContextManager {
        policy: TruncationPolicy::KeepRecent,
        recent_keep: 8,
    };

    let fitted = mgr.fit(&messages, 300);

    // Should keep some recent messages, drop older ones
    assert!(fitted.len() < messages.len(), "Should drop older messages");

    // Most recent message should be present
    assert_eq!(
        fitted.last().map(|m| &m.id),
        messages.last().map(|m| &m.id),
        "Most recent message should be preserved"
    );
}

#[test]
fn test_system_messages_always_preserved() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    // Add 3 system messages
    for i in 0..3 {
        messages.push(make_message(
            conv_id,
            MessageRole::System,
            &format!("System message {}", i),
        ));
    }

    // Add many body messages
    for i in 0..20 {
        messages.push(make_message(
            conv_id,
            MessageRole::User,
            "User message with some text content here.",
        ));
    }

    let mgr = ContextManager::default();
    let fitted = mgr.fit(&messages, 200);

    // All 3 system messages should be present
    let system_count = fitted
        .iter()
        .filter(|m| m.role == MessageRole::System)
        .count();
    assert_eq!(system_count, 3, "All system messages should be preserved");

    // First 3 should be system
    for i in 0..3 {
        assert_eq!(
            fitted[i].role,
            MessageRole::System,
            "First 3 should all be system messages"
        );
    }
}

#[test]
fn test_truncate_oldest_equivalent_to_keep_recent() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    for i in 0..10 {
        messages.push(make_message(
            conv_id,
            MessageRole::User,
            "Message with content here.",
        ));
    }

    let mgr_keep_recent = ContextManager {
        policy: TruncationPolicy::KeepRecent,
        recent_keep: 8,
    };

    let mgr_truncate = ContextManager {
        policy: TruncationPolicy::TruncateOldest,
        recent_keep: 8,
    };

    let fitted_keep = mgr_keep_recent.fit(&messages, 300);
    let fitted_truncate = mgr_truncate.fit(&messages, 300);

    // Both should behave identically
    assert_eq!(
        fitted_keep.len(),
        fitted_truncate.len(),
        "TruncateOldest should be equivalent to KeepRecent"
    );
    assert_eq!(
        fitted_keep.iter().map(|m| m.id).collect::<Vec<_>>(),
        fitted_truncate.iter().map(|m| m.id).collect::<Vec<_>>(),
        "Both policies should keep the same messages"
    );
}

#[test]
fn test_very_tight_budget_preserves_system() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    // Add system message
    messages.push(make_message(
        conv_id,
        MessageRole::System,
        "You are a helpful assistant.",
    ));

    // Add many user messages
    for i in 0..30 {
        messages.push(make_message(
            conv_id,
            MessageRole::User,
            "User message with content here.",
        ));
    }

    let mgr = ContextManager::default();
    let fitted = mgr.fit(&messages, 50); // Very tight budget

    // System message should still be there
    assert!(
        fitted.iter().any(|m| m.role == MessageRole::System),
        "System message should be preserved even with very tight budget"
    );

    // Should have system + at least a few more messages
    assert!(
        fitted.len() > 1,
        "Should fit at least system + some other messages"
    );
}

#[test]
fn test_recent_keep_count_respected() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    for i in 0..30 {
        messages.push(make_message(
            conv_id,
            MessageRole::User,
            "Message content here.",
        ));
    }

    // Test with recent_keep = 5
    let mgr = ContextManager {
        policy: TruncationPolicy::SummarizeMiddle,
        recent_keep: 5,
    };

    let fitted = mgr.fit(&messages, 500); // Loose budget

    // Count non-system messages (should respect recent_keep)
    let non_system_count = fitted
        .iter()
        .filter(|m| m.role != MessageRole::System)
        .count();

    assert!(
        non_system_count <= 5,
        "Should respect recent_keep count (expected ≤5, got {})",
        non_system_count
    );
}

#[test]
fn test_multiline_messages_truncated_correctly() {
    let conv_id = Uuid::new_v4();
    let mut messages = vec![];

    let long_content = r#"This is a multiline message with multiple sentences.
It has several lines of content here.
And this continues with more text that should be counted toward token estimation.
The token count should be significant.
"#;

    for i in 0..10 {
        messages.push(make_message(conv_id, MessageRole::User, long_content));
    }

    let mgr = ContextManager {
        policy: TruncationPolicy::KeepRecent,
        recent_keep: 8,
    };

    let fitted = mgr.fit(&messages, 300);

    // Should truncate due to multiline content
    assert!(
        fitted.len() < messages.len(),
        "Should truncate messages with significant content"
    );

    // Most recent should still be there
    assert_eq!(
        fitted.last().map(|m| &m.id),
        messages.last().map(|m| &m.id),
        "Most recent should always be kept"
    );
}
