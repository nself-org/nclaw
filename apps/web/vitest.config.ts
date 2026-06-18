/**
 * Vitest configuration for claw-web unit tests.
 *
 * Purpose: Configure the jsdom test environment for React component tests
 *          and lib/hook unit tests. Path alias @/* mirrors tsconfig.json.
 *
 * Constraints: jsdom required for React Testing Library; e2e handled by Playwright.
 */

import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test-setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
    exclude: ['node_modules', 'e2e', '**/*.spec.{ts,tsx}'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      // Ensure a single React instance across source + @testing-library/react
      'react': path.resolve(__dirname, './node_modules/react'),
      'react-dom': path.resolve(__dirname, './node_modules/react-dom'),
      'react-dom/client': path.resolve(__dirname, './node_modules/react-dom/client'),
    },
  },
});
