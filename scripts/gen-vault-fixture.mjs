// Generates fixtures/vault-v1.json from docs/vault-format.md alone.
// Deliberately independent of src/ so the TS tests act as a cross-implementation check,
// and so it doubles as a reference for the future Dart implementation.
//
// Usage: node scripts/gen-vault-fixture.mjs

import { webcrypto as crypto } from 'node:crypto';
import { writeFileSync } from 'node:fs';

const enc = new TextEncoder();
const b64 = (bytes) => Buffer.from(bytes).toString('base64');

const password = 'correct horse battery staple 记账';
const iterations = 100000;

const data = {
  schemaVersion: 1,
  accounts: [
    { id: '7d0c6a2e-1f4b-4c5e-9a3d-2b8e6f1c0a01', name: '微信', kind: 'ewallet', initialBalance: 10000, archived: false },
    { id: '7d0c6a2e-1f4b-4c5e-9a3d-2b8e6f1c0a02', name: '信用卡', kind: 'credit', initialBalance: -52000, archived: false },
  ],
  categories: [
    { id: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a01', name: '餐饮', type: 'expense', icon: '🍜', keywords: ['午饭', '咖啡'], archived: false },
    { id: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a02', name: '订阅', type: 'expense', icon: '🔁', keywords: ['iCloud'], archived: false },
    { id: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a03', name: '工资', type: 'income', icon: '💼', keywords: ['工资'], archived: false },
  ],
  transactions: [
    {
      id: 'c3a1d2e4-5f60-4718-8a9b-0c1d2e3f4a01', type: 'expense', amount: 3550,
      categoryId: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a01', accountId: '7d0c6a2e-1f4b-4c5e-9a3d-2b8e6f1c0a01',
      date: '2026-10-05', note: '午饭', createdAt: '2026-10-05T04:30:00.000Z', updatedAt: '2026-10-05T04:30:00.000Z',
    },
    {
      id: 'c3a1d2e4-5f60-4718-8a9b-0c1d2e3f4a02', type: 'expense', amount: 2100,
      categoryId: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a02', accountId: '7d0c6a2e-1f4b-4c5e-9a3d-2b8e6f1c0a02',
      date: '2026-10-01', note: 'iCloud', createdAt: '2026-10-01T01:00:00.000Z', updatedAt: '2026-10-01T01:00:00.000Z',
      recurringId: 'e9f8a7b6-c5d4-4e3f-8a1b-2c3d4e5f6a01',
    },
    {
      id: 'c3a1d2e4-5f60-4718-8a9b-0c1d2e3f4a03', type: 'income', amount: 1500000,
      categoryId: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a03', accountId: '7d0c6a2e-1f4b-4c5e-9a3d-2b8e6f1c0a01',
      date: '2026-09-30', note: '9月工资', createdAt: '2026-09-30T10:00:00.000Z', updatedAt: '2026-09-30T10:00:00.000Z',
    },
  ],
  recurring: [
    {
      id: 'e9f8a7b6-c5d4-4e3f-8a1b-2c3d4e5f6a01', name: 'iCloud 200GB', type: 'expense', amount: 2100,
      categoryId: '5b1e9f3a-8c2d-4e7f-a1b0-3c4d5e6f7a02', accountId: '7d0c6a2e-1f4b-4c5e-9a3d-2b8e6f1c0a02',
      note: 'iCloud', frequency: 'monthly', interval: 1, startDate: '2026-01-01', active: true, lastGenerated: '2026-10-01',
    },
  ],
  settings: { autoLockMinutes: 5 },
};

const salt = crypto.getRandomValues(new Uint8Array(16));
const dekRaw = crypto.getRandomValues(new Uint8Array(32));
const wrapIv = crypto.getRandomValues(new Uint8Array(12));
const payloadIv = crypto.getRandomValues(new Uint8Array(12));

const baseKey = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
const kekRaw = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, baseKey, 256);
const kek = await crypto.subtle.importKey('raw', kekRaw, 'AES-GCM', false, ['encrypt']);
const dek = await crypto.subtle.importKey('raw', dekRaw, 'AES-GCM', false, ['encrypt']);

// Key wrapping is plain AES-GCM encryption of the raw 32-byte DEK.
const wrapped = await crypto.subtle.encrypt(
  { name: 'AES-GCM', iv: wrapIv, additionalData: enc.encode('cipher-penny:v1:dek') },
  kek,
  dekRaw,
);
const payload = await crypto.subtle.encrypt(
  { name: 'AES-GCM', iv: payloadIv, additionalData: enc.encode('cipher-penny:v1:payload') },
  dek,
  enc.encode(JSON.stringify(data)),
);

const fixture = {
  description: 'Interop test vector for docs/vault-format.md v1. Opening `envelope` with `password` must yield `data`.',
  password,
  envelope: {
    format: 'cipher-penny-vault',
    version: 1,
    kdf: { name: 'PBKDF2', hash: 'SHA-256', iterations, salt: b64(salt) },
    wrappedKey: { iv: b64(wrapIv), data: b64(new Uint8Array(wrapped)) },
    payload: { iv: b64(payloadIv), data: b64(new Uint8Array(payload)) },
    updatedAt: '2026-10-05T04:30:00.000Z',
  },
  data,
};

writeFileSync(new URL('../fixtures/vault-v1.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log('wrote fixtures/vault-v1.json');
