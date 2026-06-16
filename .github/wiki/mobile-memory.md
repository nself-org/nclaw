# ɳClaw Mobile — Infinite Memory Architecture

## Overview

ɳClaw's core identity is "you just talk to it — no New Chat, auto-topics, Postgres is the brain." The mobile app (nclaw/mobile, React Native + Expo) implements this via three composable hooks that wrap the libnclaw Rust core via the JSI bridge (`@nself/native-bridge`).

## Hooks

### `useMemoryRecall`

Fetches semantically relevant memories before every chat send.

| Detail | Value |
|---|---|
| File | `nclaw/mobile/hooks/useMemoryRecall.ts` |
| JSI call | `getNcLawJSI().memorySearch(query, 5)` |
| Limit | 5 results (MEMORY_RECALL_LIMIT) |
| Format | `<memory_context>` block prepended to the prompt |
| UX | `isRecalling: true` drives the "Recalling memory..." indicator |
| Error | Captured in `error` field; never blocks the send |

**Usage in `useSendMessage`:**
```ts
const ctx = await recallForQuery(message);
const prompt = ctx ? `${ctx}\n\n${message}` : message;
```

### `useMemoryInsert`

Persists each conversation turn into libnclaw's memory store after the response is delivered.

| Detail | Value |
|---|---|
| File | `nclaw/mobile/hooks/useMemoryInsert.ts` |
| JSI call | `getNcLawJSI().memoryInsert(turn)` |
| Blocking | No — fire-and-forget; `insertMemory()` returns void |
| Concurrency | Multiple in-flight inserts are safe (Rust side is thread-safe) |
| Error | Captured in `error` field; never rethrows |

**Usage in `useSendMessage`:**
```ts
// After response delivered — do NOT await
insertMemory({ conversationId, role: 'user', content: text, model: null });
insertMemory({ conversationId, role: 'assistant', content: response, model });
```

### `useAutoTopics`

Subscribes to the `topic_auto_classify` GraphQL subscription and maintains a live deduped topic list for the Topics sidebar.

| Detail | Value |
|---|---|
| File | `nclaw/mobile/hooks/useAutoTopics.ts` |
| Subscription | `topic_auto_classify` (Hasura real-time) |
| Deduplication | By `id` — repeated rows update rather than append |
| Sort | Newest-first by `updatedAt` |
| Skip | When `userId` is undefined (unauthenticated) |

**Usage in Topics sidebar:**
```ts
const { topics, loading } = useAutoTopics(userId);
```

### `useSendMessage`

Orchestrates the full send pipeline: recall → augment → chatSend → insert.

| Detail | Value |
|---|---|
| File | `nclaw/mobile/hooks/useSendMessage.ts` |
| Status states | `idle → recalling → sending → sent / failed` |
| `isRecalling` | True during memorySearch (from useMemoryRecall) |
| `isSending` | True during recalling or sending |
| Retry | `retryLast()` resends the last message |

## Data Flow

```
User types message
        │
        ▼
useMemoryRecall.recallForQuery(message)
  → getNcLawJSI().memorySearch(message, 5)
  → formats <memory_context> block
        │
        ▼
Augmented prompt = <memory_context>\n\noriginal message
        │
        ▼
getNcLawJSI().chatSend(augmentedPrompt)
  → libnclaw inference pipeline
  → streamed response (chat_message_stream subscription)
        │
        ▼
Response delivered to user
        │
        ▼  (fire-and-forget)
useMemoryInsert.insertMemory(user turn)
useMemoryInsert.insertMemory(assistant turn)
  → getNcLawJSI().memoryInsert(turn)
  → libnclaw extracts facts/preferences/events → Postgres
```

## Auto-Topic Classification

Independently of the send pipeline, the `topic_auto_classify` Hasura subscription fires whenever the inference engine classifies a new topic from the conversation. `useAutoTopics` subscribes to this and updates the sidebar without any polling.

## JSI Interface

All JSI calls go through `@nself/native-bridge`:

```ts
import { getNcLawJSI } from '@nself/native-bridge';
// memorySearch(query: string, limit: number): Promise<Memory[]>
// memoryInsert(turn: MemoryInsertTurn): Promise<void>
```

The full interface is defined in `packages/@nself/native-bridge/src/nclaw-jsi.ts` (`NcLawJSIInterface`). The native module is registered by nclaw/mobile's bootstrap on app start (`registerNcLawJSI()`).

## Testing

Unit tests use Jest + `@testing-library/react-native`:

| Test file | Covers |
|---|---|
| `nclaw/mobile/__tests__/useMemoryRecall.test.ts` | context format, isRecalling, error, limit |
| `nclaw/mobile/__tests__/useMemoryInsert.test.ts` | fire-and-forget, error capture, concurrency |
| `nclaw/mobile/__tests__/useAutoTopics.test.ts` | dedup, sort, skip, errors |

Run: `pnpm test --filter nclaw/mobile`

## Cross-references

- T-P3-E4-W2-S3-T03 — NativeNclaw JSI bridge implementation
- T-P3-E4-W2-S3-T04 — useSendMessage base (chat send / streaming)
- T-P3-E4-W2-S3-T05 — This ticket (memory hooks)
- `packages/@nself/native-bridge/src/nclaw-jsi.ts` — NcLawJSIInterface
- `.claude/memory/project_nclaw_infinite_memory.md` — ɳClaw identity: infinite memory
