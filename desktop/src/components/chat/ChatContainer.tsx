import React from 'react';
import { useChat } from '@ai-sdk/react';
import { DefaultChatTransport, type UIMessage } from 'ai';
import { chatTransport } from '../../lib/chat-client';
import { ChatList } from './ChatList';
import { InputArea } from './InputArea';
import type { Message } from './MessageBubble';

/**
 * Top-level chat orchestrator. Wires Vercel AI SDK (v5) useChat to the Tauri
 * command bridge via chatTransport. Real LlmBackend streaming lands in S15.T17.
 */
export function ChatContainer() {
  const [input, setInput] = React.useState('');
  const { messages, status, sendMessage } = useChat({
    transport: new DefaultChatTransport({ fetch: chatTransport as typeof fetch }),
  });

  const isLoading = status === 'submitted' || status === 'streaming';

  // Map AI SDK v5 UIMessages to our Message shape for ChatList. v5 messages
  // carry an array of parts; concatenate text parts into a single string.
  const mapped: Message[] = messages.map((m: UIMessage) => ({
    id: m.id,
    role: m.role as Message['role'],
    content: m.parts
      .filter((p): p is { type: 'text'; text: string } => p.type === 'text')
      .map((p) => p.text)
      .join(''),
  }));

  function handleInputAreaChange(value: string) {
    setInput(value);
  }

  function handleSubmitWrapper() {
    const trimmed = input.trim();
    if (!trimmed || isLoading) return;
    void sendMessage({ text: trimmed });
    setInput('');
  }

  const isEmpty = messages.length === 0;

  return (
    <div className="flex flex-col h-full bg-gray-950">
      {isEmpty ? (
        <div className="flex flex-1 flex-col items-center justify-center gap-3 text-slate-400 select-none">
          {/* Placeholder for ɳ logo — real asset lands with brand sprint */}
          <div
            aria-hidden
            className="text-5xl font-bold text-sky-500 leading-none"
            style={{ fontFamily: 'system-ui, sans-serif' }}
          >
            ɳ
          </div>
          <p className="text-sm">Start a conversation. ɳClaw will remember.</p>
        </div>
      ) : (
        <ChatList messages={mapped} />
      )}

      <InputArea
        value={input}
        onChange={handleInputAreaChange}
        onSubmit={handleSubmitWrapper}
        isStreaming={isLoading}
      />
    </div>
  );
}
