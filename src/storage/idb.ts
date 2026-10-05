import { parseEnvelope, type CipherBlob, type Envelope } from '../crypto/vault-crypto';

// Only ciphertext is ever written here (AGENTS.md security rules).

const DB_NAME = 'cipher-penny';
const STORE = 'kv';
const VAULT_KEY = 'vault';
const SYNC_KEY = 'sync';

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function run<T>(mode: IDBTransactionMode, fn: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await openDb();
  try {
    return await new Promise<T>((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      const req = fn(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}

export async function loadEnvelope(): Promise<Envelope | null> {
  const value = await run<unknown>('readonly', (s) => s.get(VAULT_KEY));
  return value === undefined ? null : parseEnvelope(value);
}

export async function saveEnvelope(envelope: Envelope): Promise<void> {
  await run('readwrite', (s) => s.put(envelope, VAULT_KEY));
}

/** Device-local sync settings, encrypted with the DEK (F-SYNC-8). */
export async function loadSyncSecret(): Promise<CipherBlob | null> {
  const value = await run<unknown>('readonly', (s) => s.get(SYNC_KEY));
  return (value as CipherBlob | undefined) ?? null;
}

export async function saveSyncSecret(blob: CipherBlob): Promise<void> {
  await run('readwrite', (s) => s.put(blob, SYNC_KEY));
}

export async function deleteSyncSecret(): Promise<void> {
  await run('readwrite', (s) => s.delete(SYNC_KEY));
}

export async function clearAll(): Promise<void> {
  await run('readwrite', (s) => s.clear());
}

/** Asks the browser not to evict our storage under pressure. Best effort. */
export async function requestPersistentStorage(): Promise<boolean> {
  try {
    return (await navigator.storage?.persist?.()) ?? false;
  } catch {
    return false;
  }
}
