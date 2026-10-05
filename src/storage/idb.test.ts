import 'fake-indexeddb/auto';
import { describe, expect, it } from 'vitest';
import { createVault, MIN_ITERATIONS } from '../crypto/vault-crypto';
import { clearAll, loadEnvelope, saveEnvelope } from './idb';

describe('idb storage', () => {
  it('saves, loads and clears the envelope', async () => {
    expect(await loadEnvelope()).toBeNull();
    const { envelope } = await createVault('pw-12345678', { schemaVersion: 1 }, { iterations: MIN_ITERATIONS });
    await saveEnvelope(envelope);
    expect(await loadEnvelope()).toEqual(envelope);
    await clearAll();
    expect(await loadEnvelope()).toBeNull();
  });
});
