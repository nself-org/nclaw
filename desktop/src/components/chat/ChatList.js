import { jsx as _jsx } from "react/jsx-runtime";
import { useEffect, useRef } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { MessageBubble } from './MessageBubble';
/**
 * Virtualized message list. Renders only the visible slice of messages for
 * 60fps scroll performance regardless of conversation length.
 *
 * - estimateSize: 100 (rows are heterogeneous; measureElement refines each row)
 * - overscan: 5 (render 5 extra rows above/below viewport)
 */
export function ChatList({ messages }) {
    const parentRef = useRef(null);
    const virtualizer = useVirtualizer({
        count: messages.length,
        getScrollElement: () => parentRef.current,
        estimateSize: () => 100,
        overscan: 5,
        measureElement: typeof window !== 'undefined' &&
            navigator.userAgent.indexOf('Firefox') === -1
            ? (element) => element?.getBoundingClientRect().height
            : undefined,
    });
    // Auto-scroll to bottom when new messages arrive.
    useEffect(() => {
        if (messages.length > 0) {
            virtualizer.scrollToIndex(messages.length - 1, { align: 'end' });
        }
    }, [messages.length, virtualizer]);
    return (_jsx("div", { ref: parentRef, className: "flex-1 overflow-y-auto", style: { contain: 'strict' }, children: _jsx("div", { style: {
                height: `${virtualizer.getTotalSize()}px`,
                width: '100%',
                position: 'relative',
            }, children: virtualizer.getVirtualItems().map((virtualRow) => {
                const message = messages[virtualRow.index];
                return (_jsx("div", { "data-index": virtualRow.index, ref: virtualizer.measureElement, style: {
                        position: 'absolute',
                        top: 0,
                        left: 0,
                        width: '100%',
                        transform: `translateY(${virtualRow.start}px)`,
                    }, children: _jsx(MessageBubble, { message: message }) }, virtualRow.key));
            }) }) }));
}
