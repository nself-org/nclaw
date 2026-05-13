import React from 'react';
import { useChat } from 'ai/react';
import { chatTransport } from '../../lib/chat-client';
import { ChatList } from './ChatList';
import { InputArea } from './InputArea';
import type { Message } from './MessageBubble';

/**
 * Top-level chat orchestrator. Wires Vercel AI SDK useChat to the Tauri
 * command bridge via chatTransport. Real LlmBackend streaming lands in S15.T17.
 */
export function ChatContainer() {
  const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat({
    fetch: chatTransport as typeof fetch,
  });

  // Map AI SDK messages to our Message shape for ChatList.
  const mapped: Message[] = messages.map((m) => ({
    id: m.id,
    role: m.role as Message['role'],
    content: m.content,
  }));

  function handleInputAreaChange(value: string) {
    // Synthesise a ChangeEvent so we can reuse handleInputChange from useChat.
    handleInputChange({
      target: { value },
    } as React.ChangeEvent<HTMLInputElement>);
  }

  function handleSubmitWrapper() {
    if (!input.trim() || isLoading) return;
    handleSubmit();
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
