'use client';

/**
 * InputBar — simplified message input for ɳClaw web.
 *
 * Single-agent architecture — model selection is in /settings/models.
 * There is no multi-agent selector here, by design.
 *
 * Layout:  [Attach/More ▾]  [textarea]  [Mic]  [Send|Stop]
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ArrowUp, Brain, FileText, Mic, Paperclip, Square } from 'lucide-react';
import { useRouter } from 'next/navigation';

import api from '@/lib/api';
import { useChatStore } from '@/store/chat-store';
import type { SendMessageRequest } from '@/types';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface InputBarProps {
  conversationId?: string | null;
  topicId?: string | null;
  onConversationCreated?: (id: string) => void;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Inline transient tooltip shown below the input bar. */
function InlineTooltip({
  message,
  onClose,
}: {
  message: string;
  onClose: () => void;
}): React.ReactElement {
  useEffect(() => {
    const t = setTimeout(onClose, 3000);
    return () => clearTimeout(t);
  }, [onClose]);

  return (
    <motion.p
      initial={{ opacity: 0, y: -4 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -4 }}
      transition={{ duration: 0.15 }}
      role="status"
      aria-live="polite"
      style={{
        fontSize: '12px',
        color: 'var(--color-text-muted)',
        marginTop: '4px',
        paddingLeft: '4px',
      }}
    >
      {message}
    </motion.p>
  );
}

// ---------------------------------------------------------------------------
// Overflow menu item
// ---------------------------------------------------------------------------

interface OverflowItem {
  id: string;
  label: string;
  icon: React.ReactElement;
  onSelect: () => void;
}

function OverflowMenu({
  items,
  onClose,
}: {
  items: OverflowItem[];
  onClose: () => void;
}): React.ReactElement {
  const ref = useRef<HTMLDivElement>(null);

  // Close on outside click / Escape
  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    }
    document.addEventListener('keydown', handleKey);
    document.addEventListener('mousedown', handleClick);
    return () => {
      document.removeEventListener('keydown', handleKey);
      document.removeEventListener('mousedown', handleClick);
    };
  }, [onClose]);

  return (
    <motion.div
      ref={ref}
      role="menu"
      aria-label="More options"
      initial={{ opacity: 0, y: 6, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: 6, scale: 0.97 }}
      transition={{ duration: 0.15 }}
      style={{
        position: 'absolute',
        bottom: 'calc(100% + 8px)',
        left: 0,
        width: '180px',
        background: 'rgba(22, 22, 42, 0.97)',
        border: '1px solid var(--color-border)',
        borderRadius: '10px',
        boxShadow: 'var(--shadow-modal)',
        padding: '4px',
        zIndex: 50,
      }}
    >
      {items.map((item) => (
        <button
          key={item.id}
          role="menuitem"
          onClick={() => {
            item.onSelect();
            onClose();
          }}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '10px',
            width: '100%',
            padding: '8px 10px',
            borderRadius: '7px',
            border: 'none',
            background: 'transparent',
            color: 'var(--color-text)',
            fontSize: '13px',
            cursor: 'pointer',
            textAlign: 'left',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background =
              'rgba(255,255,255,0.06)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'transparent';
          }}
        >
          <span style={{ color: 'var(--color-text-muted)', flexShrink: 0 }} aria-hidden="true">
            {item.icon}
          </span>
          {item.label}
        </button>
      ))}
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Icon button — reusable small circle button
// ---------------------------------------------------------------------------

interface IconBtnProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  label: string;
  variant?: 'ghost' | 'primary' | 'stop';
}

function IconBtn({
  label,
  variant = 'ghost',
  children,
  style,
  ...props
}: IconBtnProps): React.ReactElement {
  const [hovered, setHovered] = useState(false);

  const base: React.CSSProperties = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: '36px',
    height: '36px',
    borderRadius: '50%',
    border: 'none',
    cursor: props.disabled ? 'not-allowed' : 'pointer',
    flexShrink: 0,
    transition: 'background var(--transition-fast), opacity var(--transition-fast)',
    opacity: props.disabled ? 0.35 : 1,
  };

  const variantStyle: React.CSSProperties =
    variant === 'primary'
      ? {
          background: hovered ? 'var(--color-primary-hover)' : 'var(--color-primary)',
          color: '#FFFFFF',
        }
      : variant === 'stop'
      ? {
          background: hovered ? 'rgba(248,113,113,0.25)' : 'rgba(248,113,113,0.15)',
          color: 'var(--color-error)',
        }
      : {
          background: hovered ? 'rgba(255,255,255,0.08)' : 'transparent',
          color: 'var(--color-text-muted)',
        };

  return (
    <button
      type="button"
      aria-label={label}
      style={{ ...base, ...variantStyle, ...style }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      {...props}
    >
      {children}
    </button>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function InputBar({
  conversationId,
  topicId,
  onConversationCreated,
}: InputBarProps): React.ReactElement {
  const router = useRouter();

  const isStreaming = useChatStore((s) => s.isStreaming);
  const setStreaming = useChatStore((s) => s.setStreaming);
  const appendMessage = useChatStore((s) => s.appendMessage);
  const appendStreamingContent = useChatStore((s) => s.appendStreamingContent);
  const clearStreamingContent = useChatStore((s) => s.clearStreamingContent);
  const updateConversation = useChatStore((s) => s.updateConversation);
  const addConversation = useChatStore((s) => s.addConversation);
  const setCurrentConversationId = useChatStore((s) => s.setCurrentConversationId);

  const [text, setText] = useState('');
  const [overflowOpen, setOverflowOpen] = useState(false);
  const [tooltip, setTooltip] = useState<string | null>(null);
  const [streamError, setStreamError] = useState<string | null>(null);

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const activeConvIdRef = useRef<string | null>(conversationId ?? null);

  // Keep ref in sync with prop changes
  useEffect(() => {
    activeConvIdRef.current = conversationId ?? null;
  }, [conversationId]);

  // Auto-grow textarea (min 1 line, max 8 lines)
  const adjustHeight = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    const lineHeight = 22; // px, matches font-size 14 * line-height 1.57
    const maxHeight = lineHeight * 8 + 24; // 8 lines + padding
    el.style.height = `${Math.min(el.scrollHeight, maxHeight)}px`;
  }, []);

  useEffect(() => {
    adjustHeight();
  }, [text, adjustHeight]);

  // Show transient tooltip
  const showTooltip = useCallback((msg: string) => {
    setTooltip(msg);
  }, []);

  const dismissTooltip = useCallback(() => setTooltip(null), []);

  // Overflow menu items
  const overflowItems: OverflowItem[] = [
    {
      id: 'attach',
      label: 'Attach file',
      icon: <Paperclip size={14} />,
      onSelect: () => showTooltip('File upload coming soon'),
    },
    {
      id: 'memory',
      label: 'Search memory',
      icon: <Brain size={14} />,
      onSelect: () => {
        router.push('/memory?focus=search');
      },
    },
    {
      id: 'template',
      label: 'Insert template',
      icon: <FileText size={14} />,
      onSelect: () => showTooltip('Templates coming soon'),
    },
  ];

  // Abort streaming
  const handleAbort = useCallback(() => {
    abortRef.current?.abort();
    setStreaming(false);
  }, [setStreaming]);

  // Send message
  const handleSend = useCallback(async () => {
    const content = text.trim();
    if (!content || isStreaming) return;

    setText('');
    setStreamError(null);

    let convId = activeConvIdRef.current;

    // Create conversation if none exists
    if (!convId) {
      const convResult = await api.createConversation(topicId ?? undefined);
      if (!convResult.ok) {
        setStreamError('Could not start conversation. Check your connection.');
        setText(content);
        return;
      }
      const conv = convResult.value;
      convId = conv.id;
      activeConvIdRef.current = conv.id;
      addConversation(conv);
      setCurrentConversationId(conv.id);
      onConversationCreated?.(conv.id);
    }

    // Append user message optimistically
    const userMsg = {
      id: `local-user-${Date.now()}`,
      conversationId: convId,
      role: 'user' as const,
      content,
      createdAt: new Date().toISOString(),
      tokens: null,
    };
    appendMessage(userMsg);

    // Prepare streaming placeholder for assistant reply.
    // The placeholder content stays empty; MessageList patches it live via
    // the streamingContent field in chat-store.
    const assistantPlaceholder = {
      id: `local-assistant-${Date.now()}`,
      conversationId: convId,
      role: 'assistant' as const,
      content: '',
      createdAt: new Date().toISOString(),
      tokens: null,
    };
    appendMessage(assistantPlaceholder);
    clearStreamingContent();
    setStreaming(true);

    const req: SendMessageRequest = {
      conversationId: convId,
      content,
      topicId: topicId ?? null,
    };

    const abort = new AbortController();
    abortRef.current = abort;

    try {
      const streamResult = await api.sendMessageRaw(req);
      if (!streamResult.ok) {
        throw new Error(streamResult.error.message);
      }
      const reader = streamResult.value.getReader();

      while (true) {
        if (abort.signal.aborted) break;
        const { done, value } = await reader.read();
        if (done) break;

        if (value.type === 'delta' && value.content) {
          // Accumulate into the streaming store field; MessageList renders it live
          appendStreamingContent(value.content);
        } else if (value.type === 'done') {
          // Server confirmed the final message id — bump conversation updatedAt
          if (value.conversationId) {
            updateConversation(value.conversationId, {
              updatedAt: new Date().toISOString(),
            });
          }
        } else if (value.type === 'error') {
          setStreamError(value.error ?? 'Stream error. Please try again.');
          break;
        }
      }
    } catch (err: unknown) {
      if (!abort.signal.aborted) {
        const msg =
          err instanceof Error ? err.message : 'Connection error. Please try again.';
        setStreamError(msg);
      }
    } finally {
      setStreaming(false);
      clearStreamingContent();
      abortRef.current = null;
    }
  }, [
    text,
    isStreaming,
    topicId,
    addConversation,
    setCurrentConversationId,
    onConversationCreated,
    appendMessage,
    appendStreamingContent,
    clearStreamingContent,
    setStreaming,
    updateConversation,
  ]);

  // Keyboard handling
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        void handleSend();
      } else if (e.key === 'Escape') {
        setText('');
        textareaRef.current?.blur();
      }
    },
    [handleSend]
  );

  const canSend = text.trim().length > 0 && !isStreaming;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
      {/* Glass-card input bar */}
      <div
        className="glass-card"
        style={{
          display: 'flex',
          alignItems: 'flex-end',
          gap: '8px',
          padding: '10px 12px',
          borderRadius: '14px',
          position: 'relative',
        }}
      >
        {/* Left — Attach / More overflow */}
        <div style={{ position: 'relative', flexShrink: 0, alignSelf: 'flex-end' }}>
          <IconBtn
            label="More options"
            variant="ghost"
            aria-haspopup="menu"
            aria-expanded={overflowOpen}
            onClick={() => setOverflowOpen((v) => !v)}
          >
            <Paperclip size={18} />
          </IconBtn>

          <AnimatePresence>
            {overflowOpen && (
              <OverflowMenu
                items={overflowItems}
                onClose={() => setOverflowOpen(false)}
              />
            )}
          </AnimatePresence>
        </div>

        {/* Textarea */}
        <textarea
          ref={textareaRef}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Ask anything..."
          rows={1}
          aria-label="Message input"
          aria-multiline="true"
          disabled={isStreaming}
          style={{
            flex: 1,
            resize: 'none',
            background: 'transparent',
            border: 'none',
            outline: 'none',
            color: 'var(--color-text)',
            fontSize: '14px',
            lineHeight: '22px',
            padding: '5px 0',
            fontFamily: 'inherit',
            overflow: 'auto',
            maxHeight: `${22 * 8 + 24}px`,
            minHeight: '32px',
          }}
        />

        {/* Right — Mic */}
        <IconBtn
          label="Voice input"
          variant="ghost"
          style={{ flexShrink: 0, alignSelf: 'flex-end' }}
          onClick={() => showTooltip('Voice input coming soon')}
          disabled={isStreaming}
        >
          <Mic size={18} />
        </IconBtn>

        {/* Right — Send / Stop */}
        {isStreaming ? (
          <IconBtn
            label="Stop generating"
            variant="stop"
            style={{ flexShrink: 0, alignSelf: 'flex-end' }}
            onClick={handleAbort}
          >
            <Square size={16} />
          </IconBtn>
        ) : (
          <IconBtn
            label="Send message"
            variant="primary"
            style={{ flexShrink: 0, alignSelf: 'flex-end' }}
            onClick={() => void handleSend()}
            disabled={!canSend}
          >
            <ArrowUp size={18} />
          </IconBtn>
        )}
      </div>

      {/* Below-bar hints row */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '0 4px',
          minHeight: '18px',
        }}
      >
        {/* Inline tooltip / stream error */}
        <AnimatePresence mode="wait">
          {streamError ? (
            <motion.p
              key="error"
              initial={{ opacity: 0, y: -4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.15 }}
              role="alert"
              aria-live="assertive"
              style={{ fontSize: '12px', color: 'var(--color-error)', margin: 0 }}
            >
              {streamError}
            </motion.p>
          ) : tooltip ? (
            <InlineTooltip
              key="tooltip"
              message={tooltip}
              onClose={dismissTooltip}
            />
          ) : (
            <span key="empty" />
          )}
        </AnimatePresence>

        {/* Keyboard shortcut hint — hidden on mobile */}
        <p
          aria-hidden="true"
          className="hidden sm:block"
          style={{
            fontSize: '11px',
            color: 'var(--color-text-muted)',
            margin: 0,
            opacity: 0.6,
            userSelect: 'none',
          }}
        >
          ↵ send &nbsp;·&nbsp; ⇧↵ newline
        </p>
      </div>

      {/* Textarea placeholder style */}
      <style>{`
        textarea[aria-label="Message input"]::placeholder {
          color: var(--color-text-placeholder);
          opacity: 1;
        }
      `}</style>
    </div>
  );
}

export default InputBar;
