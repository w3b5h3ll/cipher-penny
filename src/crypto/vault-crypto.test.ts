import { describe, expect, it } from 'vitest';
import fixture from '../../fixtures/vault-v1.json';
import { base64ToBytes, bytesToBase64 } from './base64';
import {
  changePassword,
  CorruptedVaultError,
  createVault,
  decryptLocalSecret,
  encryptLocalSecret,
  MIN_ITERATIONS,
  openPayload,
  openVault,
  parseEnvelope,
  sealVault,
  UnsupportedFormatError,
  WrongPasswordError,
  type Envelope,
} from './vault-crypto';

const fast = { iterations: MIN_ITERATIONS };
const sample = { schemaVersion: 1, note: '午饭 ¥35', list: [1, 2, 3] };

function flipByte(b64: string, index: number): string {
  const bytes = base64ToBytes(b64);
  bytes[index] = bytes[index]! ^ 0x01;
  return bytesToBase64(bytes);
}

describe('vault crypto (F-VAULT-3)', () => {
  it('round-trips with the right password', async () => {
    const { envelope } = await createVault('hunter2-long', sample, fast);
    const { data } = await openVault(envelope, 'hunter2-long');
    expect(data).toEqual(sample);
  });

  it('rejects a wrong password with WrongPasswordError', async () => {
    const { envelope } = await createVault('hunter2-long', sample, fast);
    await expect(openVault(envelope, 'hunter3-long')).rejects.toBeInstanceOf(WrongPasswordError);
  });

  it('detects tampering of the payload', async () => {
    const { envelope } = await createVault('pw-12345678', sample, fast);
    const tampered: Envelope = { ...envelope, payload: { ...envelope.payload, data: flipByte(envelope.payload.data, 3) } };
    await expect(openVault(tampered, 'pw-12345678')).rejects.toBeInstanceOf(CorruptedVaultError);
  });

  it('detects tampering of the wrapped key', async () => {
    const { envelope } = await createVault('pw-12345678', sample, fast);
    const tampered: Envelope = {
      ...envelope,
      wrappedKey: { ...envelope.wrappedKey, data: flipByte(envelope.wrappedKey.data, 0) },
    };
    await expect(openVault(tampered, 'pw-12345678')).rejects.toBeInstanceOf(WrongPasswordError);
  });

  it('uses a fresh IV for every seal', async () => {
    const { envelope, dek } = await createVault('pw-12345678', sample, fast);
    const resealed = await sealVault(envelope, dek, sample);
    expect(resealed.payload.iv).not.toBe(envelope.payload.iv);
    expect(resealed.payload.data).not.toBe(envelope.payload.data);
    expect(resealed.wrappedKey).toEqual(envelope.wrappedKey);
    expect((await openVault(resealed, 'pw-12345678')).data).toEqual(sample);
  });

  it('never stores plaintext in the envelope', async () => {
    const { envelope } = await createVault('pw-12345678', sample, fast);
    expect(JSON.stringify(envelope)).not.toContain('午饭');
  });
});

describe('changePassword (F-VAULT-5)', () => {
  it('re-wraps the DEK: new password works, old does not, data unchanged', async () => {
    const { envelope, dek } = await createVault('old-password', sample, fast);
    const changed = await changePassword(envelope, dek, 'new-password', fast);
    expect(changed.payload).toEqual(envelope.payload);
    expect(changed.kdf.salt).not.toBe(envelope.kdf.salt);
    expect((await openVault(changed, 'new-password')).data).toEqual(sample);
    await expect(openVault(changed, 'old-password')).rejects.toBeInstanceOf(WrongPasswordError);
  });
});

describe('DEK-only helpers (F-SYNC-4, F-SYNC-7, F-SYNC-8)', () => {
  it('opens a payload sealed with the same DEK and rejects another vault', async () => {
    const { envelope, dek } = await createVault('hunter2-long', sample, fast);
    const resealed = await sealVault(envelope, dek, { ...sample, note: '晚饭' });
    expect(await openPayload(resealed, dek)).toEqual({ ...sample, note: '晚饭' });
    const other = await createVault('hunter2-long', sample, fast);
    await expect(openPayload(other.envelope, dek)).rejects.toBeInstanceOf(CorruptedVaultError);
  });

  it('keeps local secrets separate from payloads', async () => {
    const { envelope, dek } = await createVault('hunter2-long', sample, fast);
    const blob = await encryptLocalSecret(dek, { token: 'github_pat_x' });
    expect(JSON.stringify(blob)).not.toContain('github_pat_x');
    expect(await decryptLocalSecret(dek, blob)).toEqual({ token: 'github_pat_x' });
    await expect(openPayload({ ...envelope, payload: blob }, dek)).rejects.toBeInstanceOf(CorruptedVaultError);
  });
});

describe('parseEnvelope (F-IO-2)', () => {
  it('accepts a valid envelope', async () => {
    const { envelope } = await createVault('pw-12345678', sample, fast);
    expect(parseEnvelope(JSON.parse(JSON.stringify(envelope)))).toEqual(envelope);
  });

  it.each([
    ['not an object', 'hello'],
    ['wrong format', { format: 'other' }],
    ['future version', { ...fixture.envelope, version: 2 }],
    ['weak kdf', { ...fixture.envelope, kdf: { ...fixture.envelope.kdf, iterations: 1000 } }],
    ['missing payload', { ...fixture.envelope, payload: undefined }],
    ['bad base64', { ...fixture.envelope, payload: { iv: '!!', data: 'abc' } }],
  ])('rejects %s', (_, value) => {
    expect(() => parseEnvelope(value)).toThrow(UnsupportedFormatError);
  });
});

describe('interop test vector fixtures/vault-v1.json (N-PORT-1)', () => {
  it('opens the independently generated vault', async () => {
    const envelope = parseEnvelope(fixture.envelope);
    const { data } = await openVault(envelope, fixture.password);
    expect(data).toEqual(fixture.data);
  });
});
