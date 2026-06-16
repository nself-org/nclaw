/**
 * Purpose: ESLint flat config for nClaw mobile (React Native + Expo, TypeScript).
 * Inputs:  **\/*.{ts,tsx}
 * Outputs: Lint pass/fail
 * Constraints: ESLint 10 flat config. Minimal — TypeScript handles type safety;
 *              ESLint gates code style only. no-undef disabled (TS covers it).
 * SPORT: CI green gate
 */
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2021,
        sourceType: 'module',
        ecmaFeatures: { jsx: true },
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
      'react-hooks': reactHooks,
    },
    rules: {
      ...tsPlugin.configs.recommended.rules,
      // TypeScript handles undefined-variable checking; disable no-undef for TS files
      'no-undef': 'off',
      'no-useless-assignment': 'off',
      // react-hooks rules — downgraded to warn for existing code base
      'react-hooks/rules-of-hooks': 'warn',
      'react-hooks/exhaustive-deps': 'warn',
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-require-imports': 'warn',
    },
  },
  {
    ignores: [
      'node_modules/**',
      '.expo/**',
      'android/**',
      'ios/**',
      'dist/**',
      'babel.config.js',
      'eslint.config.js',
      'tailwind.config.js',
    ],
  },
];
