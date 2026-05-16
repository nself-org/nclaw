import React, { useRef, useEffect, useCallback } from 'react';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';

interface Props {
  value: string;
  onChange: (value: string) => void;
  onSubmit: () => void;
  isStreaming: boolean;
}

const LINE_HEIGHT = 24; // px, matches Tailwind leading-6
const MAX_ROWS = 8;

/**
 * Multi-line chat input. Auto-grows up to MAX_ROWS, then scrolls internally.
 * Enter sends; Shift+Enter inserts newline. File paste is stubbed (v1.2.0).
 */
export function InputArea({ value, onChange, onSubmit, isStreaming }: Props) {
  const textareaRef = useRef<React.ElementRef<typeof Textarea>>(null);

  // Auto-resize on content change.
  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    const maxHeight = LINE_HEIGHT * MAX_ROWS;
    el.style.height = `${Math.min(el.scrollHeight, maxHeight)}px`;
    el.style.overflowY = el.scrollHeight > maxHeight ? 'auto' : 'hidden';
  }, [value]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLElement>) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        if (!isStreaming && value.trim()) {
          onSubmit();
        }
      }
    },
    [isStreaming, onSubmit, value]
  );

  const handlePaste = useCallback((e: React.ClipboardEvent<HTMLElement>) => {
    const hasFiles = Array.from(e.clipboardData.items).some(
      (item) => item.kind === 'file'
    );
    if (hasFiles) {
      e.preventDefault();
      console.warn('file paste deferred to v1.2.0');
    }
    // Text paste falls through to default browser handling.
  }, []);

  const disabled = isStreaming || !value.trim();

  return (
    <div className="flex items-end gap-2 px-4 py-3 border-t border-gray-800 bg-gray-950">
      <Textarea
        ref={textareaRef}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={handleKeyDown}
        onPaste={handlePaste}
        rows={1}
        placeholder="Message ɳClaw…"
        data-testid="chat-input"
        className="flex-1 resize-none rounded-xl bg-gray-800 px-4 py-2
                   text-slate-100 placeholder-gray-500 text-sm leading-6
                   min-h-[2.5rem] max-h-[12rem] min-h-0"
        style={{ overflowY: 'hidden' }}
      />
      <Button
        onClick={onSubmit}
        disabled={disabled}
        variant="default"
        size="sm"
        className="flex-shrink-0 rounded-xl bg-sky-500 text-white hover:bg-sky-400"
        aria-label="Send message"
      >
        Send
      </Button>
    </div>
  );
}
