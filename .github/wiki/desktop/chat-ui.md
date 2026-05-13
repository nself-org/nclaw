# Chat UI — ɳClaw Desktop

The chat UI is built from four components and a Tauri command bridge stub.

## Components

| Component | Path | Purpose |
|---|---|---|
| `ChatContainer` | `src/components/chat/ChatContainer.tsx` | Orchestrates `useChat`, passes state down |
| `ChatList` | `src/components/chat/ChatList.tsx` | Virtualized message list via `@tanstack/react-virtual` |
| `MessageBubble` | `src/components/chat/MessageBubble.tsx` | Renders one message with Markdown, math, and code blocks |
| `InputArea` | `src/components/chat/InputArea.tsx` | Auto-growing textarea, sends on Enter |

## Rendering pipeline

Markdown is processed by `react-markdown` with these plugins in order:

1. `remark-gfm` — tables, strikethrough, task lists
2. `remark-math` — `$inline$` and `$$block$$` math syntax
3. `rehype-sanitize` (defaultSchema) — strips `<script>`, `<iframe>`, and raw HTML
4. `rehype-katex` — renders math nodes via KaTeX

KaTeX CSS loads lazily on the first message that contains math.

Code blocks use `react-syntax-highlighter` (Prism, oneDark theme) with a copy button that appears on hover.

## Tauri bridge

`src/lib/chat-client.ts` — `chatTransport` bridges Vercel AI SDK `useChat` to the Tauri `stream_chat` command. Currently returns a single SSE chunk with the stub response. Real streaming via `LlmBackend` lands in S15.T17.

## Virtualization

`ChatList` uses `useVirtualizer` with `estimateSize: 100` and `overscan: 5`. Dynamic height measurement refines row sizes after first render, keeping scroll at 60fps regardless of conversation length.

## XSS hardening

`rehype-sanitize` with `defaultSchema` runs before `rehype-katex` in the plugin chain, blocking all raw HTML injection. User content never reaches the DOM as raw HTML.
