/**
 * Purpose: Unit tests for markdown-incremental streaming-safety utilities.
 * Inputs:  Partial markdown strings containing open code fences, math blocks, etc.
 * Outputs: Vitest pass/fail assertions.
 * Constraints: Pure TS — no DOM, no Tauri, no React needed.
 * SPORT: T-P3-E6-W2-S6-T01
 */
import { describe, it, expect } from "vitest";
import {
  hasOpenCodeFence,
  hasOpenMathBlock,
  hasOpenInlineCode,
  safeRenderText,
} from "./markdown-incremental";

describe("hasOpenCodeFence", () => {
  it("returns false for empty string", () => {
    expect(hasOpenCodeFence("")).toBe(false);
  });

  it("returns false for closed fence", () => {
    expect(hasOpenCodeFence("```js\nconsole.log(1)\n```")).toBe(false);
  });

  it("returns true for open fence", () => {
    expect(hasOpenCodeFence("```js\nconsole.log(1)")).toBe(true);
  });

  it("returns false for two open fences (double-open = even)", () => {
    // Two unclosed fences = even count → technically balanced from a parse-count POV
    expect(hasOpenCodeFence("```\n```\n```\n```")).toBe(false);
  });
});

describe("hasOpenMathBlock", () => {
  it("returns false for empty string", () => {
    expect(hasOpenMathBlock("")).toBe(false);
  });

  it("returns false for closed math block", () => {
    expect(hasOpenMathBlock("$$E=mc^2$$")).toBe(false);
  });

  it("returns true for open math block", () => {
    expect(hasOpenMathBlock("$$E=mc^2")).toBe(true);
  });
});

describe("hasOpenInlineCode", () => {
  it("returns false for balanced backtick", () => {
    expect(hasOpenInlineCode("`foo`")).toBe(false);
  });

  it("returns true for dangling backtick", () => {
    expect(hasOpenInlineCode("use `foo")).toBe(true);
  });
});

describe("safeRenderText", () => {
  it("returns original text when nothing is open", () => {
    const text = "Hello ```js\nfoo\n``` world";
    expect(safeRenderText(text)).toBe(text);
  });

  it("closes open code fence", () => {
    const result = safeRenderText("```ts\nconst x = 1");
    expect(result).toContain("```");
    // Must end with closing fence
    expect(result.endsWith("```")).toBe(true);
  });

  it("truncates open math block", () => {
    const text = "Before $$E=mc";
    const result = safeRenderText(text);
    expect(result).not.toContain("$$");
  });
});
