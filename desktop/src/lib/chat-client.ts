import { invoke } from '@tauri-apps/api/core';

interface ChatMessage {
  role: string;
  content: string;
}

/**
 * Bridges Vercel AI SDK transport to the Tauri `stream_chat` command.
 * Real streaming lands in S15.T17 when LlmBackend is wired. For now this
 * calls the stub command and wraps the reply in a single SSE chunk.
 */
export async function chatTransport(req: Request): Promise<Response> {
  const body = await req.json() as { messages: ChatMessage[] };
  const reply = await invoke<string>('stream_chat', { messages: body.messages });

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(
        encoder.encode(`data: ${JSON.stringify({ content: reply })}\n\n`)
      );
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream' },
  });
}
