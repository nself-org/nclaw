/**
 * Purpose: Generate and manage idempotency keys for mutations to prevent duplicates on retry.
 * Inputs:  mutation type (sendMessage, saveMemory, etc.)
 * Outputs: stable UUID key that persists until server confirms success
 * Constraints: Key must be stable across retries; clear only on confirmed success.
 *              Never clear on error (allows safe retry with same key).
 * SPORT: T-P3-E5-W1-S1-T05 — idempotency keys
 */

/**
 * Generate a unique idempotency key using crypto.randomUUID().
 * This key should be stored in a useRef and included in API request headers.
 *
 * @returns A UUID string suitable for use as X-Idempotency-Key header
 */
export function generateIdempotencyKey(): string {
  return crypto.randomUUID();
}

/**
 * Hook to manage idempotency keys for a mutation.
 * Stores key in useRef so it persists across component re-renders.
 * Only clears after confirmed server success.
 *
 * Usage:
 * ```tsx
 * const { key, clearKey } = useIdempotencyKey();
 *
 * const handleSend = async () => {
 *   try {
 *     const res = await fetch('/api/send', {
 *       method: 'POST',
 *       headers: { 'X-Idempotency-Key': key },
 *       body: JSON.stringify(data),
 *     });
 *     if (res.ok) {
 *       clearKey(); // Only clear after success
 *     }
 *   } catch (error) {
 *     // Do NOT clear key on error — next retry uses same key
 *   }
 * };
 * ```
 */
export function useIdempotencyKeyHook() {
  // Import React here to avoid issues in server-side code
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const React = require('react');
  const { useRef } = React as typeof import('react');

  const keyRef = useRef<string>(generateIdempotencyKey());

  const getCurrentKey = () => keyRef.current;

  const clearKey = () => {
    keyRef.current = generateIdempotencyKey();
  };

  return {
    key: getCurrentKey(),
    clearKey,
  };
}

/**
 * Non-hook version for use in standalone functions or server contexts.
 * Manages idempotency key with explicit state management.
 */
export class IdempotencyKeyManager {
  private key: string;

  constructor() {
    this.key = generateIdempotencyKey();
  }

  getKey(): string {
    return this.key;
  }

  clearKey(): void {
    this.key = generateIdempotencyKey();
  }

  /**
   * Reset to a specific key (useful for testing).
   */
  setKey(newKey: string): void {
    this.key = newKey;
  }
}
