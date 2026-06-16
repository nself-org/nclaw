# ɳClaw Mobile — Chat Architecture (GraphQL + JSI Wiring)

> Updated: T-P3-E4-W2-S3-T04 (backend wiring complete)

## Overview

The ɳClaw mobile chat surface is wired as follows:

```
User sends message
      │
      ▼
useSendMessage hook (nclaw/mobile/hooks/useSendMessage.ts)
      │
      ├─ 1. useMemoryRecall → NativeNclaw.memorySearch() [T05]
      │
      ├─ 2. Optimistic UI → message appears with 'sending' status
      │
      ├─ 3. NativeNclaw.chatSend(augmentedPrompt) [T03 JSI bridge]
      │        Returns: AI response string (full text)
      │        Rust side writes tokens to nclaw_message_tokens during inference
      │
      ├─ 4. GraphQL mutation: PersistUserMessage → nclaw_messages [urql]
      │
      ├─ 5. Status transition: 'sending' → 'sent' | 'failed'
      │
      └─ 6. useMemoryInsert → fire-and-forget turn persistence [T05]

Parallel (driven by GraphQL subscription):
      chat.tsx useSubscription (ChatMessageStream)
        │
        └─ Hasura streams nclaw_message_tokens rows → token_chunk appended
             to assistant bubble in FlatList (real-time streaming UX)
```

## Files

| File | Purpose |
|------|---------|
| `hooks/useSendMessage.ts` | Orchestrates full send lifecycle (optimistic + JSI + GraphQL + memory) |
| `services/chat.ts` | urql document nodes: `PERSIST_USER_MESSAGE` mutation + `CHAT_MESSAGE_STREAM` subscription |
| `app/(tabs)/chat.tsx` | Chat screen: FlatList + InputBar + ErrorBanner + TypingIndicator |
| `types/chat.ts` | `ChatMessage`, `MessageStatus`, `ChatError` types |
| `packages/@nself/native-bridge/src/nclaw-jsi.ts` | `NcLawJSIInterface` including `chatSend()` method |
| `packages/@nself/native-bridge/src/NclawModule.nitro.ts` | `NativeNclaw` singleton with `chatSend(message): Promise<string>` |

## Error Handling

Three typed errors via the `ChatError` discriminated union (defined in `types/chat.ts`):

| Error kind | Cause | Retry |
|---|---|---|
| `NetworkError` | Device offline or Hasura unreachable | Yes — 3× exponential backoff (1 s, 2 s, 4 s) |
| `InferenceError` | Rust libnclaw pipeline failure | Manual (retry button) |
| `RateLimitError` | Too many requests | Manual (retry button; `retryAfterMs` field) |

Errors are surfaced as an `ErrorBanner` in `chat.tsx` with a "Retry" button wired to `retryLast()`.

## Offline Queue

`PersistUserMessage` mutations use `requestPolicy: 'network-only'`. The urql offline exchange (configured in `app/_layout.tsx` via `@nself/graphql-client` `buildExchanges`) queues mutations in AsyncStorage when offline and replays them on reconnect.

## Streaming Tokens

Tokens stream via the Hasura `nclaw_message_tokens_stream` subscription:
- Subscription starts when `conversationId` is set and `isSending` is true
- Each event appends a `token_chunk` to the assistant message bubble
- `is_final = true` marks the end of streaming (`isStreaming` → false)
- The `sequence` cursor prevents duplicate token delivery on re-subscribe

## Status Machine

```
idle → (sendMessage) → recalling → (recall done) → sending → (chatSend + persist) → sent
                                                           → (error) → failed → (retryLast) → recalling
```
