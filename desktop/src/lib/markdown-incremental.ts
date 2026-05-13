/**
 * markdown-incremental — utilities for safe rendering of incomplete markdown during streaming.
 *
 * When streaming partial text that may contain incomplete code fences (```),
 * math blocks ($$), or other markdown structures, we need to prevent rendering errors.
 * This module detects open structures and offers a "safe to render" version that
 * either closes them or truncates them before render time.
 */

/**
 * Detects whether text has an open code fence (```) without a closing one.
 * Counts backtick-triplets; odd count = open.
 */
export function hasOpenCodeFence(text: string): boolean {
  const matches = text.match(/```/g);
  return matches !== null && matches.length % 2 === 1;
}

/**
 * Detects whether text has an open math block ($$) without a closing one.
 * Counts $$; odd count = open.
 */
export function hasOpenMathBlock(text: string): boolean {
  const matches = text.match(/\$\$/g);
  return matches !== null && matches.length % 2 === 1;
}

/**
 * Detects whether text has an open inline code backtick (single `) without a closing one.
 * Note: this is a naive check — does not account for escaped backticks.
 */
export function hasOpenInlineCode(text: string): boolean {
  // Count unescaped backticks
  let count = 0;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '`' && (i === 0 || text[i - 1] !== '\\')) {
      count++;
    }
  }
  return count % 2 === 1;
}

/**
 * Returns text safe to render by closing or truncating incomplete markdown structures.
 * Strategy:
 * - Open code fence: append closing ``` to prevent parser errors
 * - Open math block: truncate back to before the open $$ (prevents layout jumps)
 * - Open inline code: append closing ` (less critical, but consistent)
 */
export function safeRenderText(text: string): string {
  let out = text;

  // Handle open code fence: append visual close to prevent parser error
  if (hasOpenCodeFence(out)) {
    out += '\n```';
  }

  // Handle open math block: truncate back before the opening $$
  // (mathematical expressions are more visually disruptive to leave open)
  if (hasOpenMathBlock(out)) {
    const idx = out.lastIndexOf('$$');
    if (idx !== -1) {
      out = out.substring(0, idx);
    }
  }

  // Handle open inline code: append closing backtick
  if (hasOpenInlineCode(out)) {
    out += '`';
  }

  return out;
}

/**
 * Detects whether the text is "complete" from a markdown perspective
 * (all structures properly closed). Useful for deciding when to switch
 * from "render with guards" to "render as-is".
 */
export function isCompleteMarkdown(text: string): boolean {
  return (
    !hasOpenCodeFence(text) &&
    !hasOpenMathBlock(text) &&
    !hasOpenInlineCode(text)
  );
}
