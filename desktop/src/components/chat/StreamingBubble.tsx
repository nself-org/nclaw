import { useEffect, useState } from 'react';
import { MessageBubble } from './MessageBubble';
import type { StreamingBuffer } from '@/lib/streaming-buffer';
import { safeRenderText } from '@/lib/markdown-incremental';

interface Props {
  buffer: StreamingBuffer;
  onCancel: () => void;
}

/**
 * StreamingBubble — renders a single assistant message that updates token-by-token.
 * Subscribes to the StreamingBuffer and re-renders on each new token.
 * Provides cancel button and loading indicator while streaming is in progress.
 */
export function StreamingBubble({ buffer, onCancel }: Props) {
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
    role: 'assistant' as const,
    content: safeText,
    created_at: new Date().toISOString(),
  };

  return (
    <div className="flex flex-col gap-1 w-full">
      <MessageBubble message={message} />
      {!done && (
        <div className="flex items-center gap-2 text-xs text-slate-400 px-4 py-1">
          <span className="inline-block animate-pulse">▍</span>
          <span className="text-slate-500">Streaming...</span>
          <button
            onClick={onCancel}
            className="ml-auto px-2 py-0.5 rounded border border-slate-700
                       hover:border-sky-500 hover:text-sky-400 transition-colors
                       focus:outline-none focus:ring-2 focus:ring-sky-500"
            aria-label="Cancel stream"
          >
            Cancel
          </button>
        </div>
      )}
    </div>
  );
}
