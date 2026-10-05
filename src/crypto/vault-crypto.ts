import { base64ToBytes, bytesToBase64 } from './base64';

// Normative spec: docs/vault-format.md. Keep this file and the spec in lockstep.

export const VAULT_FORMAT = 'cipher-penny-vault';
export const VAULT_VERSION = 1;
export const DEFAULT_ITERATIONS = 600_000;
export const MIN_ITERATIONS = 100_000;
const MAX_ITERATIONS = 10_000_000;
const SALT_BYTES = 16;
const IV_BYTES = 12;
const AAD_DEK = new TextEncoder().encode('cipher-penny:v1:dek');
const AAD_PAYLOAD = new TextEncoder().encode('cipher-penny:v1:payload');

export interface CipherBlob {
  iv: string;
  data: string;
}

export interface Envelope {
  format: typeof VAULT_FORMAT;
  version: typeof VAULT_VERSION;
  kdf: { name: 'PBKDF2'; hash: 'SHA-256'; iterations: number; salt: string };
  wrappedKey: CipherBlob;
  payload: CipherBlob;
  updatedAt: string;
}

export class WrongPasswordError extends Error {
  constructor() {
    super('Wrong password');
    this.name = 'WrongPasswordError';
  }
}

export class CorruptedVaultError extends Error {
  constructor(message = 'Vault data is corrupted or has been tampered with') {
    super(message);
    this.name = 'CorruptedVaultError';
  }
}

export class UnsupportedFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UnsupportedFormatError';
  }
}

const subtle = () => globalThis.crypto.subtle;

function randomBytes(n: number): Uint8Array<ArrayBuffer> {
  return globalThis.crypto.getRandomValues(new Uint8Array(n));
}

async function deriveKek(password: string, salt: Uint8Array<ArrayBuffer>, iterations: number): Promise<CryptoKey> {
  const base = await subtle().importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
  return subtle().deriveKey(
    { name: 'PBKDF2', salt, iterations, hash: 'SHA-256' },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['wrapKey', 'unwrapKey'],
  );
}

async function wrapDek(dek: CryptoKey, password: string, iterations: number) {
  const salt = randomBytes(SALT_BYTES);
  const iv = randomBytes(IV_BYTES);
  const kek = await deriveKek(password, salt, iterations);
  const wrapped = await subtle().wrapKey('raw', dek, kek, { name: 'AES-GCM', iv, additionalData: AAD_DEK });
  return {
    kdf: { name: 'PBKDF2' as const, hash: 'SHA-256' as const, iterations, salt: bytesToBase64(salt) },
    wrappedKey: { iv: bytesToBase64(iv), data: bytesToBase64(new Uint8Array(wrapped)) },
  };
}

async function encryptPayload(dek: CryptoKey, data: unknown): Promise<CipherBlob> {
  const iv = randomBytes(IV_BYTES);
  const plaintext = new TextEncoder().encode(JSON.stringify(data));
  const ciphertext = await subtle().encrypt({ name: 'AES-GCM', iv, additionalData: AAD_PAYLOAD }, dek, plaintext);
  return { iv: bytesToBase64(iv), data: bytesToBase64(new Uint8Array(ciphertext)) };
}

export interface CreateOptions {
  iterations?: number;
  now?: Date;
}

/** Creates a new vault with a fresh random DEK (F-VAULT-1, F-VAULT-3). */
export async function createVault(
  password: string,
  data: unknown,
  options: CreateOptions = {},
): Promise<{ envelope: Envelope; dek: CryptoKey }> {
  const iterations = options.iterations ?? DEFAULT_ITERATIONS;
  // Extractable so the same DEK can be re-wrapped on password change (F-VAULT-5).
  const dek = await subtle().generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt']);
  const { kdf, wrappedKey } = await wrapDek(dek, password, iterations);
  const envelope: Envelope = {
    format: VAULT_FORMAT,
    version: VAULT_VERSION,
    kdf,
    wrappedKey,
    payload: await encryptPayload(dek, data),
    updatedAt: (options.now ?? new Date()).toISOString(),
  };
  return { envelope, dek };
}

/** Unlocks a vault. Throws WrongPasswordError or CorruptedVaultError (F-VAULT-2). */
export async function openVault(envelope: Envelope, password: string): Promise<{ data: unknown; dek: CryptoKey }> {
  const { kdf, wrappedKey, payload } = envelope;
  const kek = await deriveKek(password, base64ToBytes(kdf.salt), kdf.iterations);
  let dek: CryptoKey;
  try {
    dek = await subtle().unwrapKey(
      'raw',
      base64ToBytes(wrappedKey.data),
      kek,
      { name: 'AES-GCM', iv: base64ToBytes(wrappedKey.iv), additionalData: AAD_DEK },
      { name: 'AES-GCM' },
      true,
      ['encrypt', 'decrypt'],
    );
  } catch {
    throw new WrongPasswordError();
  }
  let plaintext: ArrayBuffer;
  try {
    plaintext = await subtle().decrypt(
      { name: 'AES-GCM', iv: base64ToBytes(payload.iv), additionalData: AAD_PAYLOAD },
      dek,
      base64ToBytes(payload.data),
    );
  } catch {
    throw new CorruptedVaultError();
  }
  try {
    return { data: JSON.parse(new TextDecoder().decode(plaintext)) as unknown, dek };
  } catch {
    throw new CorruptedVaultError('Decrypted payload is not valid JSON');
  }
}

/** Re-encrypts data with a fresh IV, keeping the KDF header and wrapped key. */
export async function sealVault(envelope: Envelope, dek: CryptoKey, data: unknown, now: Date = new Date()): Promise<Envelope> {
  return { ...envelope, payload: await encryptPayload(dek, data), updatedAt: now.toISOString() };
}

/** Re-wraps the existing DEK under a new password; the payload is unchanged (F-VAULT-5). */
export async function changePassword(
  envelope: Envelope,
  dek: CryptoKey,
  newPassword: string,
  options: CreateOptions = {},
): Promise<Envelope> {
  const { kdf, wrappedKey } = await wrapDek(dek, newPassword, options.iterations ?? DEFAULT_ITERATIONS);
  return { ...envelope, kdf, wrappedKey, updatedAt: (options.now ?? new Date()).toISOString() };
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function isBase64(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(v) && v.length % 4 === 0;
}

function isBlob(v: unknown): v is CipherBlob {
  return isRecord(v) && isBase64(v.iv) && isBase64(v.data);
}

/** Validates untrusted JSON (local storage or an imported backup) as an Envelope (F-IO-2). */
export function parseEnvelope(value: unknown): Envelope {
  if (!isRecord(value) || value.format !== VAULT_FORMAT) {
    throw new UnsupportedFormatError('不是 CipherPenny 备份文件');
  }
  if (value.version !== VAULT_VERSION) {
    throw new UnsupportedFormatError(`不支持的备份版本：${String(value.version)}`);
  }
  const { kdf, wrappedKey, payload, updatedAt } = value;
  if (
    !isRecord(kdf) ||
    kdf.name !== 'PBKDF2' ||
    kdf.hash !== 'SHA-256' ||
    typeof kdf.iterations !== 'number' ||
    !Number.isInteger(kdf.iterations) ||
    kdf.iterations < MIN_ITERATIONS ||
    kdf.iterations > MAX_ITERATIONS ||
    !isBase64(kdf.salt)
  ) {
    throw new UnsupportedFormatError('备份文件的密钥派生参数无效');
  }
  if (!isBlob(wrappedKey) || !isBlob(payload) || typeof updatedAt !== 'string') {
    throw new UnsupportedFormatError('备份文件结构不完整');
  }
  return value as unknown as Envelope;
}
