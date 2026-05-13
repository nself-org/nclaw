//! Context window management with truncation policies for nClaw.
//!
//! This module provides tools for fitting conversation message history into
//! LLM context windows while preserving system messages and maintaining
//! conversation coherence under the configured truncation policy.

use crate::types::{Message, MessageRole};
use std::collections::VecDeque;

/// Defines how to reduce message history when it exceeds the context window limit.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TruncationPolicy {
    /// Drop oldest non-system messages from the start, keeping recent ones.
    /// This is the most straightforward approach.
    KeepRecent,

    /// Keep system messages + recent N messages + a summary placeholder for dropped middle.
    /// This preserves the end of the conversation while signaling content was dropped.
    /// **Default policy.**
    SummarizeMiddle,

    /// Alias for KeepRecent — drops oldest messages at message-level boundaries.
    TruncateOldest,
}

impl Default for TruncationPolicy {
    fn default() -> Self {
        TruncationPolicy::SummarizeMiddle
    }
}

/// Manages fitting conversation message history into a context window budget.
///
/// # Example
///
/// ```ignore
/// let mgr = ContextManager::default();
/// let fitted = mgr.fit(&messages, 4096);
/// // fitted now contains system messages + recent messages (or summary) that fit
/// ```
#[derive(Debug, Clone)]
pub struct ContextManager {
    /// Policy for truncating messages when they exceed the budget.
    pub policy: TruncationPolicy,

    /// Number of most recent messages to keep when summarizing middle.
    /// Default: 8.
    pub recent_keep: usize,
}

impl Default for ContextManager {
    fn default() -> Self {
        Self {
            policy: TruncationPolicy::default(),
            recent_keep: 8,
        }
    }
}

impl ContextManager {
    /// Creates a new ContextManager with the given policy and recent_keep count.
    pub fn new(policy: TruncationPolicy, recent_keep: usize) -> Self {
        Self {
            policy,
            recent_keep,
        }
    }

    /// Fits message history into the given token budget using the configured policy.
    ///
    /// Returns a possibly-truncated message list whose total estimated tokens
    /// fit within `max_tokens`. System messages are always preserved and placed first.
    ///
    /// # Token Estimation
    ///
    /// Uses a simple heuristic: ~4 characters per token. Real tokenization
    /// is plugged in at the backend/LLM layer (T02).
    pub fn fit(&self, messages: &[Message], max_tokens: u32) -> Vec<Message> {
        if messages.is_empty() {
            return vec![];
        }

        let total_tokens: u32 = messages.iter().map(estimate_tokens).sum();
        if total_tokens <= max_tokens {
            return messages.to_vec();
        }

        // Always preserve all system messages at the top.
        let (mut system_msgs, body): (Vec<_>, Vec<_>) = messages
            .iter()
            .cloned()
            .partition(|m| m.role == MessageRole::System);

        // Apply the configured truncation policy.
        let mut output = match self.policy {
            TruncationPolicy::KeepRecent | TruncationPolicy::TruncateOldest => {
                // Drop oldest messages from the body until we fit.
                let mut kept: VecDeque<Message> = body.into();
                let sys_tokens: u32 = system_msgs.iter().map(estimate_tokens).sum();

                while !kept.is_empty() {
                    let body_tokens: u32 = kept.iter().map(estimate_tokens).sum();
                    if sys_tokens + body_tokens <= max_tokens {
                        break;
                    }
                    kept.pop_front(); // Drop oldest
                }

                system_msgs.extend(kept);
                system_msgs
            }

            TruncationPolicy::SummarizeMiddle => {
                // Keep recent_keep most recent + insert a summary placeholder.
                let n = body.len();
                let recent_n = self.recent_keep.min(n);
                let dropped_count = n.saturating_sub(recent_n);

                if dropped_count > 0 {
                    let summary_msg = Message {
                        id: uuid::Uuid::new_v4(),
                        conversation_id: body
                            .first()
                            .map(|m| m.conversation_id)
                            .unwrap_or_else(uuid::Uuid::new_v4),
                        role: MessageRole::System,
                        content: crate::types::MessageContent::Text(format!(
                            "[{} earlier messages were dropped for context length. Summary will be inserted here.]",
                            dropped_count
                        )),
                        created_at: chrono::Utc::now(),
                        model: None,
                        tool_calls: vec![],
                        metadata: crate::types::MessageMetadata::default(),
                    };
                    system_msgs.push(summary_msg);
                }

                // Add the recent messages.
                let recent = &body[n.saturating_sub(recent_n)..];
                system_msgs.extend_from_slice(recent);
                system_msgs
            }
        };

        // Final sanity check: if we still don't fit, aggressively drop from the start.
        let final_tokens: u32 = output.iter().map(estimate_tokens).sum();
        if final_tokens > max_tokens {
            // Keep system messages and drop from the start of body.
            let sys_count = output
                .iter()
                .take_while(|m| m.role == MessageRole::System)
                .count();
            let body_start = sys_count;

            while output.len() > body_start
                && output.iter().map(estimate_tokens).sum::<u32>() > max_tokens
            {
                output.remove(body_start);
            }
        }

        output
    }
}

/// Estimates the token count for a single message using a simple heuristic.
///
/// Assumes ~4 characters per token. This is a rough approximation;
/// actual tokenization is provided by the backend (e.g., tokenizers crate).
fn estimate_tokens(msg: &Message) -> u32 {
    let content_len = match &msg.content {
        crate::types::MessageContent::Text(s) => s.len(),
        crate::types::MessageContent::Parts(parts) => {
            parts.iter().map(|p| estimate_part_tokens(p) as usize).sum()
        }
    };

    // Rough estimate: role name + content + metadata overhead
    let total_chars = msg.role.as_str().len() + content_len + 8;
    ((total_chars + 3) / 4) as u32
}

/// Estimates tokens for a ContentPart.
fn estimate_part_tokens(part: &crate::types::ContentPart) -> u32 {
    use crate::types::ContentPart;

    let chars = match part {
        ContentPart::Text { text } => text.len(),
        ContentPart::Image { url, mime_type } => url.len() + mime_type.len(),
        ContentPart::File {
            url,
            name,
            mime_type,
        } => url.len() + name.len() + mime_type.len(),
        ContentPart::ToolResult {
            tool_call_id,
            content,
            ..
        } => tool_call_id.len() + content.len(),
    };

    ((chars + 3) / 4) as u32
}

impl MessageRole {
    /// Returns the string representation of the role for token counting.
    fn as_str(&self) -> &'static str {
        match self {
            MessageRole::User => "user",
            MessageRole::Assistant => "assistant",
            MessageRole::System => "system",
            MessageRole::Tool => "tool",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
            messages.push(Message {
                id: uuid::Uuid::new_v4(),
                conversation_id: conv_id,
                role: if i % 2 == 0 {
                    MessageRole::User
                } else {
                    MessageRole::Assistant
                },
                content: crate::types::MessageContent::Text("short".to_string()),
                created_at: chrono::Utc::now(),
                model: None,
                tool_calls: vec![],
                metadata: crate::types::MessageMetadata::default(),
            });
        }

        let mgr = ContextManager::default();
        let fitted = mgr.fit(&messages, 10000);

        // All should fit
        assert_eq!(fitted.len(), 5);
    }

    #[test]
    fn test_keep_recent_policy() {
        let conv_id = uuid::Uuid::new_v4();
        let mut messages = vec![];

        // Add 10 user/assistant pairs
        for i in 0..10 {
            messages.push(Message {
                id: uuid::Uuid::new_v4(),
                conversation_id: conv_id,
                role: MessageRole::User,
                content: crate::types::MessageContent::Text(
                    "This is a message with some text content.".to_string(),
                ),
                created_at: chrono::Utc::now(),
                model: None,
                tool_calls: vec![],
                metadata: crate::types::MessageMetadata::default(),
            });
        }

        let mgr = ContextManager {
            policy: TruncationPolicy::KeepRecent,
            recent_keep: 8,
        };

        let fitted = mgr.fit(&messages, 300);

        // Should keep some recent messages, drop older ones
        assert!(fitted.len() < messages.len());
        // Most recent message should be present
        assert_eq!(fitted.last().map(|m| &m.id), messages.last().map(|m| &m.id));
    }

    #[test]
    fn test_summarize_middle_policy() {
        let conv_id = uuid::Uuid::new_v4();
        let mut messages = vec![];

        // Add system message first
        messages.push(Message {
            id: uuid::Uuid::new_v4(),
            conversation_id: conv_id,
            role: MessageRole::System,
            content: crate::types::MessageContent::Text("You are a helpful assistant.".to_string()),
            created_at: chrono::Utc::now(),
            model: None,
            tool_calls: vec![],
            metadata: crate::types::MessageMetadata::default(),
        });

        // Add many body messages
        for i in 0..20 {
            messages.push(Message {
                id: uuid::Uuid::new_v4(),
                conversation_id: conv_id,
                role: if i % 2 == 0 {
                    MessageRole::User
                } else {
                    MessageRole::Assistant
                },
                content: crate::types::MessageContent::Text(
                    "This is a message with some text content.".to_string(),
                ),
                created_at: chrono::Utc::now(),
                model: None,
                tool_calls: vec![],
                metadata: crate::types::MessageMetadata::default(),
            });
        }

        let mgr = ContextManager {
            policy: TruncationPolicy::SummarizeMiddle,
            recent_keep: 8,
        };

        let fitted = mgr.fit(&messages, 400);

        // Should have system + placeholder + recent messages
        assert!(fitted.len() > 1);
        assert!(fitted.len() <= 10); // system + placeholder + 8 recent max

        // First message should be system
        assert_eq!(fitted.first().map(|m| &m.role), Some(&MessageRole::System));

        // Should have a summary placeholder
        let has_summary = fitted.iter().any(|m| {
            m.role == MessageRole::System
                && m.content
                    .as_text()
                    .map_or(false, |t| t.contains("earlier messages"))
        });
        assert!(has_summary);

        // Last message should be from original body (recent)
        assert_eq!(fitted.last().map(|m| &m.id), messages.last().map(|m| &m.id));
    }

    #[test]
    fn test_system_messages_always_preserved() {
        let conv_id = uuid::Uuid::new_v4();
        let mut messages = vec![];

        // Add 3 system messages
        for i in 0..3 {
            messages.push(Message {
                id: uuid::Uuid::new_v4(),
                conversation_id: conv_id,
                role: MessageRole::System,
                content: crate::types::MessageContent::Text(format!("System message {}", i)),
                created_at: chrono::Utc::now(),
                model: None,
                tool_calls: vec![],
                metadata: crate::types::MessageMetadata::default(),
            });
        }

        // Add many body messages
        for i in 0..20 {
            messages.push(Message {
                id: uuid::Uuid::new_v4(),
                conversation_id: conv_id,
                role: MessageRole::User,
                content: crate::types::MessageContent::Text(
                    "User message with some text content here.".to_string(),
                ),
                created_at: chrono::Utc::now(),
                model: None,
                tool_calls: vec![],
                metadata: crate::types::MessageMetadata::default(),
            });
        }

        let mgr = ContextManager::default();
        let fitted = mgr.fit(&messages, 200);

        // All 3 system messages should be present
        let system_count = fitted
            .iter()
            .filter(|m| m.role == MessageRole::System)
            .count();
        assert_eq!(system_count, 3);

        // First 3 should be the original system messages
        for i in 0..3 {
            assert_eq!(fitted[i].role, MessageRole::System);
        }
    }

    #[test]
    fn test_truncate_oldest_alias() {
        let conv_id = uuid::Uuid::new_v4();
        let mut messages = vec![];

        for i in 0..10 {
            messages.push(Message {
                id: uuid::Uuid::new_v4(),
                conversation_id: conv_id,
                role: MessageRole::User,
                content: crate::types::MessageContent::Text(
                    "Message with content here.".to_string(),
                ),
                created_at: chrono::Utc::now(),
                model: None,
                tool_calls: vec![],
                metadata: crate::types::MessageMetadata::default(),
            });
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

        // Both should behave the same
        assert_eq!(fitted_keep.len(), fitted_truncate.len());
        assert_eq!(
            fitted_keep.iter().map(|m| m.id).collect::<Vec<_>>(),
            fitted_truncate.iter().map(|m| m.id).collect::<Vec<_>>()
        );
    }

    #[test]
    fn test_estimate_tokens() {
        let conv_id = uuid::Uuid::new_v4();

        let msg_short = Message {
            id: uuid::Uuid::new_v4(),
            conversation_id: conv_id,
            role: MessageRole::User,
            content: crate::types::MessageContent::Text("Hi".to_string()),
            created_at: chrono::Utc::now(),
            model: None,
            tool_calls: vec![],
            metadata: crate::types::MessageMetadata::default(),
        };

        let msg_long = Message {
            id: uuid::Uuid::new_v4(),
            conversation_id: conv_id,
            role: MessageRole::User,
            content: crate::types::MessageContent::Text(
                "This is a much longer message with a lot more content that should result in a higher token count estimate."
                    .to_string(),
            ),
            created_at: chrono::Utc::now(),
            model: None,
            tool_calls: vec![],
            metadata: crate::types::MessageMetadata::default(),
        };

        let short_tokens = estimate_tokens(&msg_short);
        let long_tokens = estimate_tokens(&msg_long);

        // Longer message should have more estimated tokens
        assert!(long_tokens > short_tokens);
    }
}
