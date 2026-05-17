import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { MessageBubble } from './MessageBubble';
import type { StreamingBuffer } from '@/lib/streaming-buffer';
import { safeRenderText } from '@/lib/markdown-incremental';
import { useStreamMetrics } from '@/hooks/useStreamMetrics';

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
  const metrics = useStreamMetrics(buffer);

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

          {/* T04 — TPS + TTFT metrics pill */}
          {(metrics.tps !== null || metrics.ttft_ms !== null) && (
            <span
              className="rounded bg-slate-800 px-1.5 py-0.5 font-mono text-slate-400 tabular-nums"
              aria-label="Streaming metrics"
            >
              {metrics.tps !== null && (
                <span title="Tokens per second">{metrics.tps} t/s</span>
              )}
              {metrics.tps !== null && metrics.ttft_ms !== null && (
                <span className="mx-1 text-slate-600">·</span>
              )}
              {metrics.ttft_ms !== null && (
                <span title="Time to first token">{metrics.ttft_ms} ms TTFT</span>
              )}
            </span>
          )}

          <Button
            onClick={onCancel}
            variant="outline"
            size="sm"
            className="ml-auto px-2 py-0.5 h-auto rounded border-slate-700
                       hover:border-sky-500 hover:text-sky-400"
            aria-label="Cancel stream"
          >
            Cancel
          </Button>
        </div>
      )}
    </div>
  );
}
