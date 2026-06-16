/**
 * nclaw/mobile — chat.ts — GraphQL operations for AI chat send/receive/stream.
 *
 * Purpose: All GraphQL mutations and subscriptions for the chat surface.
 *          Defines urql document nodes for message persistence and streaming
 *          token delivery via the Hasura chat_message_stream subscription.
 *
 * Inputs:  conversationId, messageId — correlation IDs from NcLawJSI.chatSend().
 * Outputs: Typed urql mutation/subscription document nodes consumed by
 *          useSendMessage and useMessageStream hooks.
 *
 * Constraints:
 *   - Uses urql (not Apollo) — matches @nself/graphql-client exchange stack.
 *   - Subscriptions require a WebSocket exchange in the urql client (configured
 *     in app/_layout.tsx via @nself/graphql-client buildExchanges).
 *   - Operation names match the Hasura action/subscription names defined in
 *     T-P3-E4-W1-S1-T01 feature spec §6 GraphQL Operations.
 *   - No business logic here — pure GraphQL DSL + TypeScript types.
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T-P3-E4-W2-S3-T04 (useSendMessage, useMessageStream)
 *            T-P3-E4-W1-S1-T01 feature spec §6 (operation names)
 */

import { gql } from 'urql';

// =============================================================================
// Shared chat types
// =============================================================================

/** Lifecycle status of an outgoing user message. */
export type MessageStatus = 'sending' | 'sent' | 'failed';

/**
 * Discriminated union of all chat-level errors surfaced to the UI.
 *
 * NetworkError   — device offline or Hasura unreachable.
 * InferenceError — libnclaw pipeline failure (model error, context overflow, etc.).
 * RateLimitError — too many requests; retryAfterMs contains the backoff.
 */
export type ChatError =
  | { readonly kind: 'NetworkError'; readonly message: string }
  | { readonly kind: 'InferenceError'; readonly message: string; readonly code: string }
  | { readonly kind: 'RateLimitError'; readonly message: string; readonly retryAfterMs: number };

/** A single chat message as rendered in the FlatList. */
export interface ChatMessage {
  /** Stable client-assigned UUID for optimistic list rendering. */
  readonly id: string;
  /** Server-assigned conversation this message belongs to. */
  readonly conversationId: string;
  /** 'user' for outgoing, 'assistant' for streamed AI response. */
  readonly role: 'user' | 'assistant';
  /** Message text — updated token-by-token for assistant messages during streaming. */
  content: string;
  /** Lifecycle status (user messages only; assistant messages don't have a status). */
  status: MessageStatus | null;
  /** ISO-8601 timestamp. */
  readonly createdAt: string;
  /** True while the inference pipeline is still producing tokens. */
  isStreaming: boolean;
}

// =============================================================================
// GraphQL mutation — persist a user message turn
// =============================================================================

/**
 * PersistUserMessage — insert a confirmed user message into nclaw_messages.
 *
 * Called by useSendMessage after NcLawJSI.chatSend() resolves successfully.
 * The conversationId and messageId come from the JSI result, ensuring the
 * server-side Rust inference is already correlated with the DB row.
 */
export const PERSIST_USER_MESSAGE = gql`
  mutation PersistUserMessage(
    $conversationId: uuid!
    $messageId: uuid!
    $content: String!
  ) {
    insert_nclaw_messages_one(
      object: {
        id: $messageId
        conversation_id: $conversationId
        role: "user"
        content: $content
        status: "sent"
      }
      on_conflict: {
        constraint: nclaw_messages_pkey
        update_columns: [status]
      }
    ) {
      id
      conversation_id
      content
      status
      created_at
    }
  }
`;

export interface PersistUserMessageVariables {
  conversationId: string;
  messageId: string;
  content: string;
}

export interface PersistUserMessageData {
  insert_nclaw_messages_one: {
    id: string;
    conversation_id: string;
    content: string;
    status: string;
    created_at: string;
  } | null;
}

// =============================================================================
// GraphQL subscription — streaming token delivery
// =============================================================================

/**
 * ChatMessageStream — subscribe to inference token delivery for a conversation.
 *
 * Hasura streams new rows from nclaw_message_tokens as libnclaw writes them.
 * The subscription resolves incrementally — each event appends a token chunk
 * to the assistant's message bubble in the FlatList.
 *
 * cursor.initial_value.sequence starts at 0 for each new inference run.
 * The subscription auto-terminates when is_final = true is received.
 */
export const CHAT_MESSAGE_STREAM = gql`
  subscription ChatMessageStream(
    $conversationId: uuid!
    $afterSequence: Int!
  ) {
    nclaw_message_tokens_stream(
      batch_size: 10
      cursor: { initial_value: { sequence: $afterSequence }, ordering: ASC }
      where: { conversation_id: { _eq: $conversationId } }
    ) {
      message_id
      token_chunk
      sequence
      is_final
      created_at
    }
  }
`;

export interface ChatMessageStreamVariables {
  conversationId: string;
  afterSequence: number;
}

export interface TokenRow {
  message_id: string;
  token_chunk: string;
  sequence: number;
  is_final: boolean;
  created_at: string;
}

export interface ChatMessageStreamData {
  nclaw_message_tokens_stream: TokenRow[];
}

// =============================================================================
// Offline queue — @nself/graphql-client mutation queuing config
// =============================================================================

/**
 * OFFLINE_REQUEST_POLICY — urql request policy for chat mutations.
 *
 * urql's 'network-only' policy re-queues mutations when the exchange detects
 * the device is offline (via the offline exchange in @nself/graphql-client's
 * buildExchanges). Mutations are persisted to AsyncStorage and replayed when
 * connectivity is restored.
 *
 * Usage: pass as requestPolicy in useMutation context options for
 *        PERSIST_USER_MESSAGE calls.
 */
export const OFFLINE_REQUEST_POLICY = 'network-only' as const;
