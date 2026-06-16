/**
 * Purpose: Vitest global test setup for ɳClaw Desktop — polyfills + Tauri mock reset.
 * Inputs:  Loaded by vitest setupFiles before each test suite.
 * Outputs: Extended DOM + mocked Tauri bridge.
 * Constraints: jsdom does not implement scrollIntoView, ResizeObserver, or matchMedia.
 * SPORT: T-P3-E6-W2-S6-T01
 */
import "@testing-library/jest-dom";
import { vi, beforeEach } from "vitest";

// Mock @tauri-apps/api/core globally — no native bridge in test env.
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn().mockResolvedValue(undefined),
}));

beforeEach(() => {
  vi.clearAllMocks();
});

// jsdom does not implement scrollIntoView.
window.HTMLElement.prototype.scrollIntoView = vi.fn();

// jsdom lacks ResizeObserver.
global.ResizeObserver = class ResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
};

// jsdom lacks matchMedia.
Object.defineProperty(window, "matchMedia", {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});
