import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import React from 'react';
import { useChat } from '@ai-sdk/react';
import { DefaultChatTransport } from 'ai';
import { chatTransport } from '../../lib/chat-client';
import { ChatList } from './ChatList';
import { InputArea } from './InputArea';
/**
 * Top-level chat orchestrator. Wires Vercel AI SDK (v5) useChat to the Tauri
 * command bridge via chatTransport. Real LlmBackend streaming lands in S15.T17.
 */
export function ChatContainer() {
    const [input, setInput] = React.useState('');
    const { messages, status, sendMessage } = useChat({
        transport: new DefaultChatTransport({ fetch: chatTransport }),
    });
    const isLoading = status === 'submitted' || status === 'streaming';
    // Map AI SDK v5 UIMessages to our Message shape for ChatList. v5 messages
    // carry an array of parts; concatenate text parts into a single string.
    const mapped = messages.map((m) => ({
        id: m.id,
        role: m.role,
        content: m.parts
            .filter((p) => p.type === 'text')
            .map((p) => p.text)
            .join(''),
    }));
    function handleInputAreaChange(value) {
        setInput(value);
    }
    function handleSubmitWrapper() {
        const trimmed = input.trim();
        if (!trimmed || isLoading)
            return;
        void sendMessage({ text: trimmed });
        setInput('');
    }
    const isEmpty = messages.length === 0;
    return (_jsxs("div", { className: "flex flex-col h-full bg-gray-950", children: [isEmpty ? (_jsxs("div", { className: "flex flex-1 flex-col items-center justify-center gap-3 text-slate-400 select-none", children: [_jsx("div", { "aria-hidden": true, className: "text-5xl font-bold text-sky-500 leading-none", style: { fontFamily: 'system-ui, sans-serif' }, children: "\u0273" }), _jsx("p", { className: "text-sm", children: "Start a conversation. \u0273Claw will remember." })] })) : (_jsx(ChatList, { messages: mapped })), _jsx(InputArea, { value: input, onChange: handleInputAreaChange, onSubmit: handleSubmitWrapper, isStreaming: isLoading })] }));
}
