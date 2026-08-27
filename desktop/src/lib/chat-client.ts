import { invoke } from '@tauri-apps/api/core';

interface ChatMessage {
  role: string;
  content: string;
}

/**
 * Bridges Vercel AI SDK transport to the Tauri `stream_chat` command.
 * Real streaming lands in S15.T17 when LlmBackend is wired. For now this
 * calls the stub command and wraps the reply as a single-chunk UI Message
 * Stream (the protocol @ai-sdk/react's useChat/DefaultChatTransport parses
 * as of AI SDK v6 — see `ai`'s src/ui-message-stream/ui-message-chunks.ts).
 * A prior version emitted an ad hoc `{"content": ...}` SSE payload left over
 * from an older SDK version; DefaultChatTransport's strict chunk schema
 * rejects unrecognized shapes, so no message ever reached the UI.
 *
 * DefaultChatTransport calls its fetch override as fetch(url, init) — the
 * standard two-argument form, not fetch(Request) — so this must accept both
 * to satisfy the `typeof fetch` cast in ChatContainer.tsx. A prior version
 * only accepted `Request` and called req.json(), which throws immediately
 * since `input` here is the API url string, not a Request.
 */
export async function chatTransport(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const bodyText = input instanceof Request ? await input.text() : ((init?.body as string) ?? '{}');
  const body = JSON.parse(bodyText) as { messages: ChatMessage[] };
  const reply = await invoke<string>('stream_chat', { messages: body.messages });

  const encoder = new TextEncoder();
  const messageId = crypto.randomUUID();
  const chunk = (part: Record<string, unknown>) =>
    encoder.encode(`data: ${JSON.stringify(part)}\n\n`);

  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(chunk({ type: 'text-start', id: messageId }));
      controller.enqueue(chunk({ type: 'text-delta', id: messageId, delta: reply }));
      controller.enqueue(chunk({ type: 'text-end', id: messageId }));
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'x-vercel-ai-ui-message-stream': 'v1',
    },
  });
}
