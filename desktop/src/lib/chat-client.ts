import { invoke } from '@tauri-apps/api/core';

interface ChatMessage {
  role: string;
  content: string;
}

/**
 * Bridges Vercel AI SDK transport to the Tauri `stream_chat` command.
 * Real streaming lands in S15.T17 when LlmBackend is wired. For now this
 * calls the stub command and wraps the reply in the AI SDK v3 Data Stream
 * Protocol format so useChat can display the message.
 *
 * AI SDK v3 Data Stream Protocol:
 *   text part  → `0:"<text chunk>"\n`
 *   finish     → `d:{"finishReason":"stop",...}\n`
 *
 * The AI SDK calls the custom fetch as fetch(url, init) — not as fetch(Request).
 * We accept both forms via the standard fetch overload signature.
 */
export async function chatTransport(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  let bodyText: string;
  if (input instanceof Request) {
    bodyText = await input.text();
  } else {
    bodyText = (init?.body as string) ?? '{}';
  }
  const body = JSON.parse(bodyText) as { messages: ChatMessage[] };
  const reply = await invoke<string>('stream_chat', { messages: body.messages });

  const text = typeof reply === 'string' ? reply : '';
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      // Emit text delta in AI SDK v3 Data Stream Protocol format.
      controller.enqueue(encoder.encode(`0:${JSON.stringify(text)}\n`));
      // Emit finish_message part (code `d`).
      controller.enqueue(
        encoder.encode(
          `d:${JSON.stringify({ finishReason: 'stop', usage: { promptTokens: 0, completionTokens: 0 } })}\n`
        )
      );
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream', 'x-vercel-ai-data-stream': 'v1' },
  });
}
