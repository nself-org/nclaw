import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useRef, useEffect, useCallback } from 'react';
const LINE_HEIGHT = 24; // px, matches Tailwind leading-6
const MAX_ROWS = 8;
/**
 * Multi-line chat input. Auto-grows up to MAX_ROWS, then scrolls internally.
 * Enter sends; Shift+Enter inserts newline. File paste is stubbed (v1.2.0).
 */
export function InputArea({ value, onChange, onSubmit, isStreaming }) {
    const textareaRef = useRef(null);
    // Auto-resize on content change.
    useEffect(() => {
        const el = textareaRef.current;
        if (!el)
            return;
        el.style.height = 'auto';
        const maxHeight = LINE_HEIGHT * MAX_ROWS;
        el.style.height = `${Math.min(el.scrollHeight, maxHeight)}px`;
        el.style.overflowY = el.scrollHeight > maxHeight ? 'auto' : 'hidden';
    }, [value]);
    const handleKeyDown = useCallback((e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            if (!isStreaming && value.trim()) {
                onSubmit();
            }
        }
    }, [isStreaming, onSubmit, value]);
    const handlePaste = useCallback((e) => {
        const hasFiles = Array.from(e.clipboardData.items).some((item) => item.kind === 'file');
        if (hasFiles) {
            e.preventDefault();
            console.warn('file paste deferred to v1.2.0');
        }
        // Text paste falls through to default browser handling.
    }, []);
    const disabled = isStreaming || !value.trim();
    return (_jsxs("div", { className: "flex items-end gap-2 px-4 py-3 border-t border-gray-800 bg-gray-950", children: [_jsx("textarea", { ref: textareaRef, value: value, onChange: (e) => onChange(e.target.value), onKeyDown: handleKeyDown, onPaste: handlePaste, rows: 1, placeholder: "Message \u0273Claw\u2026", className: "flex-1 resize-none rounded-xl bg-gray-800 px-4 py-2\n                   text-slate-100 placeholder-gray-500 text-sm leading-6\n                   focus:outline-none focus:ring-2 focus:ring-sky-500\n                   min-h-[2.5rem] max-h-[12rem]", style: { overflowY: 'hidden' } }), _jsx("button", { onClick: onSubmit, disabled: disabled, className: "flex-shrink-0 rounded-xl px-4 py-2 text-sm font-medium\n                   bg-sky-500 text-white transition-opacity\n                   disabled:opacity-40 disabled:cursor-not-allowed\n                   hover:not-disabled:bg-sky-400 focus:outline-none\n                   focus:ring-2 focus:ring-sky-500", "aria-label": "Send message", children: "Send" })] }));
}
