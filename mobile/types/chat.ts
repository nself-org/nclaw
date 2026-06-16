/**
 * Purpose: Shared TypeScript types for ɳClaw mobile chat UI.
 * Inputs:  Consumed by chat screen, history screen, sub-thread screen.
 * Outputs: Strict typed interfaces for messages, conversations, topics.
 * Constraints: Types must mirror nclaw core protocol (libnclaw FFI surface).
 *   No runtime values here — types only.
 * SPORT: None — SPORT updated in T09.
 */

/** Sender role in a chat message. */
export type MessageRole = 'user' | 'assistant' | 'system';

/**
 * Lifecycle status of an outgoing user message (T04 — backend wiring).
 * 'sending' — JSI + GraphQL in-flight; optimistic bubble visible.
 * 'sent'    — confirmed by GraphQL mutation.
 * 'failed'  — send failed; retry button shown.
 */
export type MessageStatus = 'sending' | 'sent' | 'failed';

/**
 * Discriminated union of all chat-level errors (T04 — backend wiring).
 * NetworkError   — device offline or Hasura unreachable; supports exponential-backoff retry.
 * InferenceError — libnclaw pipeline failure (model error, context overflow, etc.).
 * RateLimitError — request rate exceeded; retryAfterMs specifies the backoff duration.
 */
export type ChatError =
  | { readonly kind: 'NetworkError'; readonly message: string }
  | { readonly kind: 'InferenceError'; readonly message: string; readonly code: string }
  | { readonly kind: 'RateLimitError'; readonly message: string; readonly retryAfterMs: number };

/** A single chat message displayed in the chat FlatList. */
export interface ChatMessage {
  /** Unique message ID (UUID). */
  id: string;
  /** Role determines bubble variant (sent vs received). */
  role: MessageRole;
  /** Message text content. May contain markdown. */
  content: string;
  /** UTC ISO timestamp when the message was created. */
  createdAt: string;
  /** Thread ID this message belongs to (conversationId). */
  threadId: string;
  /** True while an assistant message is still streaming tokens. */
  isStreaming?: boolean;
  /** Lifecycle status — user messages only. Null / undefined for assistant messages. */
  status?: MessageStatus | null;
  /** Attached file metadata — populated when a file was sent. */
  attachment?: MessageAttachment;
}

/** Metadata for a file attachment on a chat message. */
export interface MessageAttachment {
  /** File name as displayed to the user. */
  name: string;
  /** MIME type of the attachment. */
  mimeType: string;
  /** File size in bytes. */
  size: number;
  /** Local URI on-device (pre-upload) or server URI (post-upload). */
  uri: string;
}

/**
 * A conversation thread — the unit displayed in the history list.
 * Grouped by topicId in the SectionList.
 */
export interface ConversationThread {
  /** Unique thread ID (UUID). */
  id: string;
  /** Short title derived from first user message or AI-generated. */
  title: string;
  /** UTC ISO timestamp of the last message. */
  updatedAt: string;
  /** Auto-topic canonical tag assigned to this thread. */
  topicId: string | null;
  /** Preview of the last message (first 100 chars). */
  preview: string;
  /** Total message count in this thread. */
  messageCount: number;
}

/**
 * An auto-topic group header for the history SectionList.
 */
export interface TopicSection {
  /** Canonical topic tag (e.g. "code", "planning", "personal"). */
  topicId: string;
  /** Human-readable display label for the topic. */
  label: string;
  /** Threads belonging to this topic. */
  data: ConversationThread[];
}

/** Canonical auto-topic tags from the feature spec §2. */
export type AutoTopicTag =
  | 'code'
  | 'infra'
  | 'admin'
  | 'personal'
  | 'research'
  | 'question'
  | 'task'
  | 'planning'
  | 'general';

/** A topic node displayed in the topics sidebar/drawer. */
export interface TopicNode {
  /** Topic tag (canonical). */
  id: AutoTopicTag | string;
  /** Display label. */
  label: string;
  /** Number of threads with this topic. */
  threadCount: number;
  /** Whether this is a user-created manual topic (not auto-generated). */
  isManual: boolean;
}

/** User profile fields for the settings profile screen. */
export interface UserProfile {
  /** Display name. */
  displayName: string;
  /** Email address. */
  email: string;
  /** Optional avatar URI. */
  avatarUri?: string;
}

/** App display theme preference. */
export type ThemePreference = 'light' | 'dark' | 'system';

/** Notification preference toggles. */
export interface NotificationPreferences {
  /** Enable daily digest push notifications. */
  digestEnabled: boolean;
  /** Enable mention/reply push notifications. */
  mentionEnabled: boolean;
  /** Enable background-sync completion notifications. */
  syncEnabled: boolean;
}

/** App settings shape persisted in secure store. */
export interface AppSettings {
  theme: ThemePreference;
  notifications: NotificationPreferences;
  /** Active locale code (e.g. 'en', 'ar'). */
  locale: string;
}

/** A picked file for the attachment picker. */
export interface PickedFile {
  /** Local file URI. */
  uri: string;
  /** File name. */
  name: string;
  /** MIME type. */
  mimeType: string;
  /** File size in bytes. */
  size: number;
}

/** Search result item for the cross-conversation search screen. */
export interface SearchResult {
  /** Message ID. */
  messageId: string;
  /** Thread ID containing this message. */
  threadId: string;
  /** Thread title. */
  threadTitle: string;
  /** Matched message content snippet with highlight markers. */
  snippet: string;
  /** UTC ISO timestamp. */
  createdAt: string;
}
