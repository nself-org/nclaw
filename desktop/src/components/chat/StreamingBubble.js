import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { MessageBubble } from './MessageBubble';
import { safeRenderText } from '@/lib/markdown-incremental';
/**
 * StreamingBubble — renders a single assistant message that updates token-by-token.
 * Subscribes to the StreamingBuffer and re-renders on each new token.
 * Provides cancel button and loading indicator while streaming is in progress.
 */
export function StreamingBubble({ buffer, onCancel }) {
    const [text, setText] = useState(buffer.current());
    const [done, setDone] = useState(buffer.isDone());
    useEffect(() => {
        // Subscribe to buffer updates
        const unsubscribe = buffer.subscribe((updatedText) => {
            setText(updatedText);
            if (buffer.isDone()) {
                setDone(true);
            }
        });
        // Initial state in case buffer already has content
        if (buffer.isDone()) {
            setDone(true);
        }
        return () => {
            unsubscribe();
        };
    }, [buffer]);
    // Apply safe rendering guards for incomplete markdown
    const safeText = safeRenderText(text);
    // Create a synthetic message object for MessageBubble
    const message = {
        id: 'streaming',
        role: 'assistant',
        content: safeText,
        created_at: new Date().toISOString(),
    };
    return (_jsxs("div", { className: "flex flex-col gap-1 w-full", children: [_jsx(MessageBubble, { message: message }), !done && (_jsxs("div", { className: "flex items-center gap-2 text-xs text-slate-400 px-4 py-1", children: [_jsx("span", { className: "inline-block animate-pulse", children: "\u258D" }), _jsx("span", { className: "text-slate-500", children: "Streaming..." }), _jsx("button", { onClick: onCancel, className: "ml-auto px-2 py-0.5 rounded border border-slate-700\n                       hover:border-sky-500 hover:text-sky-400 transition-colors\n                       focus:outline-none focus:ring-2 focus:ring-sky-500", "aria-label": "Cancel stream", children: "Cancel" })] }))] }));
}
