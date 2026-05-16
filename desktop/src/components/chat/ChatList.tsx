import { useEffect, useRef } from 'react';
import * as ScrollAreaPrimitive from '@radix-ui/react-scroll-area';
import { useVirtualizer } from '@tanstack/react-virtual';
import { MessageBubble, Message } from './MessageBubble';

interface Props {
  messages: Message[];
}

/**
 * Virtualized message list. Renders only the visible slice of messages for
 * 60fps scroll performance regardless of conversation length.
 *
 * Uses ScrollAreaPrimitive.Viewport directly so the virtualizer can obtain
 * a ref to the actual scrollable element (ScrollArea Root has overflow:hidden).
 *
 * - estimateSize: 100 (rows are heterogeneous; measureElement refines each row)
 * - overscan: 5 (render 5 extra rows above/below viewport)
 */
export function ChatList({ messages }: Props) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: messages.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 100,
    overscan: 5,
    measureElement:
      typeof window !== 'undefined' &&
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

  return (
    <ScrollAreaPrimitive.Root className="flex-1 relative overflow-hidden" style={{ contain: 'strict' }}>
      <ScrollAreaPrimitive.Viewport ref={parentRef} className="h-full w-full">
        <div
          style={{
            height: `${virtualizer.getTotalSize()}px`,
            width: '100%',
            position: 'relative',
          }}
        >
          {virtualizer.getVirtualItems().map((virtualRow) => {
            const message = messages[virtualRow.index];
            return (
              <div
                key={virtualRow.key}
                data-index={virtualRow.index}
                ref={virtualizer.measureElement}
                style={{
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  width: '100%',
                  transform: `translateY(${virtualRow.start}px)`,
                }}
              >
                <MessageBubble message={message} />
              </div>
            );
          })}
        </div>
      </ScrollAreaPrimitive.Viewport>
      <ScrollAreaPrimitive.ScrollAreaScrollbar
        orientation="vertical"
        className="flex touch-none select-none transition-colors h-full w-2.5 border-l border-l-transparent p-[1px]"
      >
        <ScrollAreaPrimitive.ScrollAreaThumb className="relative flex-1 rounded-full bg-border" />
      </ScrollAreaPrimitive.ScrollAreaScrollbar>
      <ScrollAreaPrimitive.Corner />
    </ScrollAreaPrimitive.Root>
  );
}
