import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useChat } from 'ai/react';
import { chatTransport } from '../../lib/chat-client';
import { ChatList } from './ChatList';
import { InputArea } from './InputArea';
/**
 * Top-level chat orchestrator. Wires Vercel AI SDK useChat to the Tauri
 * command bridge via chatTransport. Real LlmBackend streaming lands in S15.T17.
 */
export function ChatContainer() {
    const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat({
        fetch: chatTransport,
    });
    // Map AI SDK messages to our Message shape for ChatList.
    const mapped = messages.map((m) => ({
        id: m.id,
        role: m.role,
        content: m.content,
    }));
    function handleInputAreaChange(value) {
        // Synthesise a ChangeEvent so we can reuse handleInputChange from useChat.
        handleInputChange({
            target: { value },
        });
    }
    function handleSubmitWrapper() {
        if (!input.trim() || isLoading)
            return;
        handleSubmit();
    }
    const isEmpty = messages.length === 0;
    return (_jsxs("div", { className: "flex flex-col h-full bg-gray-950", children: [isEmpty ? (_jsxs("div", { className: "flex flex-1 flex-col items-center justify-center gap-3 text-slate-400 select-none", children: [_jsx("div", { "aria-hidden": true, className: "text-5xl font-bold text-sky-500 leading-none", style: { fontFamily: 'system-ui, sans-serif' }, children: "\u0273" }), _jsx("p", { className: "text-sm", children: "Start a conversation. \u0273Claw will remember." })] })) : (_jsx(ChatList, { messages: mapped })), _jsx(InputArea, { value: input, onChange: handleInputAreaChange, onSubmit: handleSubmitWrapper, isStreaming: isLoading })] }));
}
