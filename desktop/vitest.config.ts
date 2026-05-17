import { defineConfig } from 'vitest/config'
import { resolve } from 'path'

export default defineConfig({
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: { provider: 'v8', include: ['src/lib/**', 'src/stores/**'] },
    css: false,
    exclude: ['**/node_modules/**', '**/dist/**', 'tests/e2e/**', 'src/**/*.js'],
    passWithNoTests: true,
  },
  resolve: { alias: { '@': resolve(__dirname, './src') } },
})
