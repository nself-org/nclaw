/**
 * Test suite for idempotency key management.
 * Validates: key generation, stability across retries, clearing on success.
 */

import { describe, it, expect } from 'vitest';
import { generateIdempotencyKey, IdempotencyKeyManager } from '../idempotency';

describe('generateIdempotencyKey', () => {
  it('generates a UUID string', () => {
    const key = generateIdempotencyKey();
    expect(typeof key).toBe('string');
    // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    expect(key).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it('generates unique keys on each call', () => {
    const key1 = generateIdempotencyKey();
    const key2 = generateIdempotencyKey();
    expect(key1).not.toBe(key2);
  });
});

describe('IdempotencyKeyManager', () => {
  it('initializes with a valid key', () => {
    const manager = new IdempotencyKeyManager();
    const key = manager.getKey();
    expect(key).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it('returns the same key on multiple getKey calls', () => {
    const manager = new IdempotencyKeyManager();
    const key1 = manager.getKey();
    const key2 = manager.getKey();
    expect(key1).toBe(key2);
  });

  it('generates a new key on clearKey', () => {
    const manager = new IdempotencyKeyManager();
    const oldKey = manager.getKey();
    manager.clearKey();
    const newKey = manager.getKey();
    expect(oldKey).not.toBe(newKey);
  });

  it('allows manual key setting via setKey', () => {
    const manager = new IdempotencyKeyManager();
    const customKey = 'custom-key-12345';
    manager.setKey(customKey);
    expect(manager.getKey()).toBe(customKey);
  });

  it('maintains key stability across multiple operations', () => {
    const manager = new IdempotencyKeyManager();
    const key1 = manager.getKey();
    // Simulate multiple retries without clearing
    const key2 = manager.getKey();
    const key3 = manager.getKey();
    expect(key1).toBe(key2);
    expect(key2).toBe(key3);
  });

  it('simulates request retry pattern: same key until success, new key on success', () => {
    const manager = new IdempotencyKeyManager();

    // First attempt
    const attemptKey1 = manager.getKey();

    // Retry with same key (error occurred)
    const attemptKey2 = manager.getKey();

    // Both retries use the same key
    expect(attemptKey1).toBe(attemptKey2);

    // Clear key after success
    manager.clearKey();
    const newKey = manager.getKey();

    // New key is different
    expect(newKey).not.toBe(attemptKey1);
  });

  it('handles rapid successive clearKey calls', () => {
    const manager = new IdempotencyKeyManager();
    manager.clearKey();
    const key1 = manager.getKey();
    manager.clearKey();
    const key2 = manager.getKey();
    expect(key1).not.toBe(key2);
  });
});
