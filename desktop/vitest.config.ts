/**
 * Purpose: Vitest configuration for ɳClaw Desktop unit + lib tests.
 * Inputs:  src/**\/*.test.{ts,tsx}
 * Outputs: Test run + coverage report
 * Constraints: jsdom env; Tauri API mocked via vi.mock; no native bridge.
 * SPORT: T-P3-E6-W2-S6-T01
 */
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    globals: true,
    exclude: ["src-tauri/**", "tests/e2e/**", "*.config.*", "node_modules"],
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov"],
      exclude: ["src-tauri/**", "tests/**", "*.config.*"],
    },
  },
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
});
