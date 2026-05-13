# Streaming Response Renderer

The Tauri desktop client supports token-by-token streaming responses from the ɳClaw backend. This enables real-time feedback for AI-generated content.

## Components

### StreamingBuffer
A pub/sub buffer that accumulates tokens and notifies subscribers on each append. Supports abort via `cancel()`.

```ts
const buffer = new StreamingBuffer();
buffer.subscribe(text => console.log(text)); // Updated on each token
buffer.append('Hello ');
buffer.append('world');
buffer.finish();
```

### markdown-incremental
Guards against rendering errors from incomplete markdown during streaming. Detects open code fences, math blocks, and inline code, then either closes or truncates them for safe rendering.

```ts
const partial = 'Some code:\n```typescript';
const safe = safeRenderText(partial); // → 'Some code:\n```typescript\n```'
```

### StreamingBubble
React component that renders a single assistant message updating token-by-token. Provides a cancel button and loading indicator.

```tsx
<StreamingBubble buffer={buffer} onCancel={handleCancel} />
```

## Integration

Wire up in `ChatContainer` when switching from one-shot to streaming responses (planned for S15.T17).

The buffer pattern decouples the transport layer (invoke/streaming) from rendering, allowing flexible response handling.
