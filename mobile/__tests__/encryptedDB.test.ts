/**
 * Unit tests — EncryptedDB service.
 *
 * Purpose: Verify schema setup, CRUD operations, key derivation logic,
 *          and idempotent open() behaviour without requiring a native SQLCipher lib.
 *
 * Inputs:  Mocked @op-engineering/op-sqlite and @nself/native-bridge SecureStore.
 *          Mocked @nself/errors ok/err/isOk utilities.
 * Outputs: Assertions on DB key management, table CRUD, error propagation,
 *          and fail-closed behaviour on SecureStore failures.
 *
 * Constraints:
 *   - No native module required — all op-sqlite calls are stubbed.
 *   - EncryptedDB._instance must be reset between tests (use afterEach close()).
 *   - Key must never appear in error messages produced by the service.
 */

import { ok, err, isOk } from '@nself/errors';
import type { SecureStoreInterface } from '@nself/native-bridge';
import { EncryptedDB, type LocalMessage, type LocalDraft } from '../services/encryptedDB';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const mockExecuteAsync = jest.fn<
  Promise<{ rows: { _array: unknown[] } }>,
  [string, unknown[]?]
>();
const mockClose = jest.fn<Promise<void>, []>().mockResolvedValue(undefined);

jest.mock('@op-engineering/op-sqlite', () => ({
  open: jest.fn(() => ({
    executeAsync: mockExecuteAsync,
    close: mockClose,
  })),
}));

// ---------------------------------------------------------------------------
// SecureStore helpers
// ---------------------------------------------------------------------------

function makeSecureStore(
  overrides: Partial<{
    getItem: SecureStoreInterface['getItem'];
    setItem: SecureStoreInterface['setItem'];
    deleteItem: SecureStoreInterface['deleteItem'];
  }> = {},
): SecureStoreInterface {
  return {
    getItem: overrides.getItem ?? jest.fn().mockResolvedValue(ok(null)),
    setItem: overrides.setItem ?? jest.fn().mockResolvedValue(ok(undefined)),
    deleteItem: overrides.deleteItem ?? jest.fn().mockResolvedValue(ok(undefined)),
  };
}

// ---------------------------------------------------------------------------
// Setup / teardown
// ---------------------------------------------------------------------------

beforeEach(() => {
  jest.clearAllMocks();
  // DDL + any CRUD executions return empty rows by default.
  mockExecuteAsync.mockResolvedValue({ rows: { _array: [] } });
});

afterEach(async () => {
  // Reset singleton so each test starts fresh.
  // Access via the private static — cast to any only in tests.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const instance = (EncryptedDB as any)._instance as EncryptedDB | null;
  if (instance !== null) {
    await instance.close();
  }
});

// ---------------------------------------------------------------------------
// open() — key derivation
// ---------------------------------------------------------------------------

describe('EncryptedDB.open — key derivation', () => {
  it('generates and stores a new key when SecureStore is empty', async () => {
    const setItem = jest.fn().mockResolvedValue(ok(undefined));
    const secureStore = makeSecureStore({ setItem });

    const result = await EncryptedDB.open(secureStore);

    expect(isOk(result)).toBe(true);
    expect(setItem).toHaveBeenCalledTimes(1);
    const [key, value] = setItem.mock.calls[0] as [string, string];
    expect(key).toBe('nclaw_db_key');
    // Key must be a 64-char hex string (32 bytes).
    expect(value).toMatch(/^[0-9a-f]{64}$/);
  });

  it('reuses an existing key from SecureStore', async () => {
    const existingKey = 'a'.repeat(64);
    const getItem = jest.fn().mockResolvedValue(ok(existingKey));
    const setItem = jest.fn().mockResolvedValue(ok(undefined));
    const secureStore = makeSecureStore({ getItem, setItem });

    const result = await EncryptedDB.open(secureStore);

    expect(isOk(result)).toBe(true);
    // setItem must NOT be called when a key already exists.
    expect(setItem).not.toHaveBeenCalled();
  });

  it('returns Err and does not open DB when SecureStore.getItem fails', async () => {
    const getItem = jest.fn().mockResolvedValue(
      err({ code: 'internal', message: 'keychain unavailable', status: 500 }),
    );
    const secureStore = makeSecureStore({ getItem });

    const result = await EncryptedDB.open(secureStore);

    expect(isOk(result)).toBe(false);
    // op-sqlite open must not be called.
    const opsqlite = require('@op-engineering/op-sqlite') as { open: jest.Mock };
    expect(opsqlite.open).not.toHaveBeenCalled();
  });

  it('returns Err when SecureStore.setItem fails during key generation', async () => {
    const setItem = jest.fn().mockResolvedValue(
      err({ code: 'internal', message: 'keychain locked', status: 500 }),
    );
    const secureStore = makeSecureStore({ setItem });

    const result = await EncryptedDB.open(secureStore);

    expect(isOk(result)).toBe(false);
  });

  it('is idempotent — returns the same instance on second call', async () => {
    const secureStore = makeSecureStore();
    const result1 = await EncryptedDB.open(secureStore);
    const result2 = await EncryptedDB.open(secureStore);

    expect(isOk(result1)).toBe(true);
    expect(isOk(result2)).toBe(true);
    if (isOk(result1) && isOk(result2)) {
      expect(result1.value).toBe(result2.value);
    }
  });
});

// ---------------------------------------------------------------------------
// Schema DDL
// ---------------------------------------------------------------------------

describe('EncryptedDB.open — schema DDL', () => {
  it('executes CREATE TABLE IF NOT EXISTS for all three tables', async () => {
    const secureStore = makeSecureStore();
    await EncryptedDB.open(secureStore);

    const calls = mockExecuteAsync.mock.calls.map(([sql]) => sql as string);
    expect(calls.some(s => s.includes('CREATE TABLE IF NOT EXISTS nclaw_messages'))).toBe(true);
    expect(calls.some(s => s.includes('CREATE TABLE IF NOT EXISTS nclaw_action_queue'))).toBe(true);
    expect(calls.some(s => s.includes('CREATE TABLE IF NOT EXISTS nclaw_drafts'))).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// insertMessage / getMessagesByThread
// ---------------------------------------------------------------------------

describe('insertMessage / getMessagesByThread', () => {
  async function openDB() {
    const secureStore = makeSecureStore();
    const result = await EncryptedDB.open(secureStore);
    if (!isOk(result)) throw new Error('DB open failed');
    return result.value;
  }

  const sampleMsg: LocalMessage = {
    id: 'msg-1',
    thread_id: 'thread-1',
    role: 'user',
    content: 'Hello',
    created_at: '2026-01-01T00:00:00Z',
  };

  it('insertMessage returns Ok(undefined) on success', async () => {
    const db = await openDB();
    mockExecuteAsync.mockResolvedValueOnce({ rows: { _array: [] } });

    const result = await db.insertMessage(sampleMsg);

    expect(isOk(result)).toBe(true);
  });

  it('insertMessage returns Err on DB failure', async () => {
    const db = await openDB();
    mockExecuteAsync.mockRejectedValueOnce(new Error('disk full'));

    const result = await db.insertMessage(sampleMsg);

    expect(isOk(result)).toBe(false);
    if (!isOk(result)) {
      expect(result.error.code).toBe('internal');
    }
  });

  it('getMessagesByThread returns rows from the DB', async () => {
    const db = await openDB();
    mockExecuteAsync.mockResolvedValueOnce({
      rows: { _array: [sampleMsg] },
    });

    const result = await db.getMessagesByThread('thread-1');

    expect(isOk(result)).toBe(true);
    if (isOk(result)) {
      expect(result.value).toHaveLength(1);
      expect(result.value[0]?.id).toBe('msg-1');
    }
  });
});

// ---------------------------------------------------------------------------
// saveDraft / getDraft / deleteDraft
// ---------------------------------------------------------------------------

describe('draft CRUD', () => {
  async function openDB() {
    const secureStore = makeSecureStore();
    const result = await EncryptedDB.open(secureStore);
    if (!isOk(result)) throw new Error('DB open failed');
    return result.value;
  }

  const sampleDraft: LocalDraft = {
    thread_id: 'thread-draft-1',
    content: 'Draft text',
    updated_at: '2026-01-01T00:00:00Z',
  };

  it('saveDraft returns Ok and getDraft returns the saved draft', async () => {
    const db = await openDB();
    mockExecuteAsync
      .mockResolvedValueOnce({ rows: { _array: [] } }) // saveDraft
      .mockResolvedValueOnce({ rows: { _array: [sampleDraft] } }); // getDraft

    const saveResult = await db.saveDraft(sampleDraft);
    expect(isOk(saveResult)).toBe(true);

    const getResult = await db.getDraft('thread-draft-1');
    expect(isOk(getResult)).toBe(true);
    if (isOk(getResult)) {
      expect(getResult.value?.content).toBe('Draft text');
    }
  });

  it('getDraft returns Ok(null) when thread has no draft', async () => {
    const db = await openDB();
    mockExecuteAsync.mockResolvedValueOnce({ rows: { _array: [] } });

    const result = await db.getDraft('no-draft-thread');

    expect(isOk(result)).toBe(true);
    if (isOk(result)) {
      expect(result.value).toBeNull();
    }
  });

  it('deleteDraft returns Ok on success', async () => {
    const db = await openDB();
    mockExecuteAsync.mockResolvedValueOnce({ rows: { _array: [] } });

    const result = await db.deleteDraft('thread-draft-1');

    expect(isOk(result)).toBe(true);
  });
});
