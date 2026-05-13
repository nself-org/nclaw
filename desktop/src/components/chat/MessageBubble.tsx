import React, { useEffect, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import rehypeSanitize, { defaultSchema } from 'rehype-sanitize';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneDark } from 'react-syntax-highlighter/dist/esm/styles/prism';

export interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
}

interface Props {
  message: Message;
}

let katexLoaded = false;

function loadKatexCss() {
  if (katexLoaded) return;
  katexLoaded = true;
  import('katex/dist/katex.min.css' as never).catch(() => {
    // Silently ignore — katex rendering still works without the external CSS
    // in most Tauri WebView environments.
  });
}

function CodeBlock({
  children,
  className,
}: {
  children?: React.ReactNode;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);
  const language = /language-(\w+)/.exec(className ?? '')?.[1] ?? 'text';
  const code = String(children).replace(/\n$/, '');

  function handleCopy() {
    navigator.clipboard.writeText(code).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  }

  return (
    <div className="relative group">
      <button
        onClick={handleCopy}
        className="absolute top-2 right-2 px-2 py-0.5 text-xs rounded
                   bg-gray-700 text-slate-300 opacity-0 group-hover:opacity-100
                   transition-opacity focus:outline-none focus:ring-2 focus:ring-sky-500"
        aria-label="Copy code"
      >
        {copied ? 'Copied!' : 'Copy'}
      </button>
      <SyntaxHighlighter
        style={oneDark}
        language={language}
        PreTag="div"
        customStyle={{ borderRadius: '0.375rem', fontSize: '0.85em' }}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  );
}

const rehypePlugins = [
  [rehypeSanitize, defaultSchema] as [typeof rehypeSanitize, typeof defaultSchema],
  rehypeKatex,
];

export const MessageBubble = React.memo(function MessageBubble({ message }: Props) {
  const hasMath =
    message.content.includes('$') || message.content.includes('\\(');

  const loadedRef = useRef(false);
  useEffect(() => {
    if (hasMath && !loadedRef.current) {
      loadedRef.current = true;
      loadKatexCss();
    }
  }, [hasMath]);

  const wrapperClass = {
    user: 'flex justify-end',
    assistant: 'flex justify-start',
    system: 'flex justify-center',
  }[message.role];

  const bubbleClass = {
    user: 'bg-gray-800 text-slate-100 max-w-[70%] rounded-2xl px-4 py-2',
    assistant: 'bg-gray-900 text-slate-100 max-w-[70%] rounded-2xl px-4 py-2',
    system: 'bg-gray-700 text-slate-300 italic max-w-[80%] rounded-xl px-4 py-2 text-sm',
  }[message.role];

  return (
    <div className={`${wrapperClass} px-4 py-1`}>
      <div className={bubbleClass}>
        <ReactMarkdown
          remarkPlugins={[remarkGfm, remarkMath]}
          rehypePlugins={rehypePlugins as never}
          components={{
            code({ className, children, ...props }) {
              const isBlock = /language-/.test(className ?? '');
              if (isBlock) {
                return (
                  <CodeBlock className={className}>{children}</CodeBlock>
                );
              }
              return (
                <code
                  className="bg-gray-700 rounded px-1 py-0.5 text-sm font-mono"
                  {...props}
                >
                  {children}
                </code>
              );
            },
          }}
        >
          {message.content}
        </ReactMarkdown>
      </div>
    </div>
  );
});
