import { todayISO } from '../core/dates';
import { createDefaultVault } from '../core/defaults';
import type { VaultData } from '../core/model';
import { applyRecurring } from '../core/recurring';
import { assertVaultData } from '../core/validate';
import {
  changePassword as rewrapPassword,
  createVault,
  DEFAULT_ITERATIONS,
  openVault,
  sealVault,
  type Envelope,
} from '../crypto/vault-crypto';
import { clearAll, loadEnvelope, requestPersistentStorage, saveEnvelope } from '../storage/idb';

export type SessionState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'empty' }
  | { status: 'locked' }
  | { status: 'unlocked'; data: VaultData; recurringCreated: number; saveError?: string };

const SAVE_DEBOUNCE_MS = 300;
const AUTO_LOCK_CHECK_MS = 10_000;

let iterations = DEFAULT_ITERATIONS;
let state: SessionState = { status: 'loading' };
const listeners = new Set<() => void>();

// Secrets live only in these closures, and only while unlocked (F-VAULT-4).
let envelope: Envelope | null = null;
let dek: CryptoKey | null = null;

let dirty = false;
let saveTimer: ReturnType<typeof setTimeout> | undefined;
let saveChain: Promise<void> = Promise.resolve();
let lastActivity = Date.now();
let autoLockTimer: ReturnType<typeof setInterval> | undefined;

function setState(next: SessionState) {
  state = next;
  for (const l of listeners) l();
}

function unlockedData(): VaultData {
  if (state.status !== 'unlocked') throw new Error('Vault is locked');
  return state.data;
}

async function persist(): Promise<void> {
  if (!dirty || !envelope || !dek || state.status !== 'unlocked') return;
  dirty = false;
  const data = state.data;
  try {
    envelope = await sealVault(envelope, dek, data);
    await saveEnvelope(envelope);
    if (state.status === 'unlocked' && state.saveError) setState({ ...state, saveError: undefined });
  } catch (err) {
    dirty = true;
    if (state.status === 'unlocked') {
      setState({ ...state, saveError: err instanceof Error ? err.message : String(err) });
    }
  }
}

function scheduleSave() {
  dirty = true;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => void flush(), SAVE_DEBOUNCE_MS);
}

/** Writes pending changes now. Saves are serialised so they land in order. */
function flush(): Promise<void> {
  clearTimeout(saveTimer);
  saveChain = saveChain.then(persist);
  return saveChain;
}

function enterUnlocked(env: Envelope, key: CryptoKey, data: VaultData) {
  envelope = env;
  dek = key;
  const { data: withRecurring, created } = applyRecurring(data, todayISO());
  setState({ status: 'unlocked', data: withRecurring, recurringCreated: created });
  if (created > 0) scheduleSave();
  startAutoLock();
}

function onActivity() {
  lastActivity = Date.now();
}

function checkAutoLock() {
  if (state.status !== 'unlocked') return;
  const minutes = state.data.settings.autoLockMinutes;
  if (minutes > 0 && Date.now() - lastActivity > minutes * 60_000) void session.lock();
}

function onVisibilityChange() {
  if (document.visibilityState === 'hidden') void flush();
  else checkAutoLock();
}

function startAutoLock() {
  lastActivity = Date.now();
  if (typeof window === 'undefined' || autoLockTimer) return;
  for (const ev of ['pointerdown', 'keydown', 'wheel', 'touchstart'] as const) {
    window.addEventListener(ev, onActivity, { passive: true });
  }
  document.addEventListener('visibilitychange', onVisibilityChange);
  window.addEventListener('pagehide', onPageHide);
  autoLockTimer = setInterval(checkAutoLock, AUTO_LOCK_CHECK_MS);
}

function onPageHide() {
  void flush();
}

function stopAutoLock() {
  if (typeof window === 'undefined' || !autoLockTimer) return;
  for (const ev of ['pointerdown', 'keydown', 'wheel', 'touchstart'] as const) {
    window.removeEventListener(ev, onActivity);
  }
  document.removeEventListener('visibilitychange', onVisibilityChange);
  window.removeEventListener('pagehide', onPageHide);
  clearInterval(autoLockTimer);
  autoLockTimer = undefined;
}

export const session = {
  getState: (): SessionState => state,

  subscribe(listener: () => void): () => void {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },

  /** For tests only: lower the KDF cost. */
  configure(options: { iterations: number }) {
    iterations = options.iterations;
  },

  async init(): Promise<void> {
    try {
      envelope = await loadEnvelope();
      setState({ status: envelope ? 'locked' : 'empty' });
    } catch (err) {
      setState({ status: 'error', message: err instanceof Error ? err.message : String(err) });
    }
  },

  /** F-VAULT-1 */
  async create(password: string): Promise<void> {
    const data = createDefaultVault();
    const created = await createVault(password, data, { iterations });
    await saveEnvelope(created.envelope);
    void requestPersistentStorage();
    enterUnlocked(created.envelope, created.dek, data);
  },

  /** F-VAULT-2. Throws WrongPasswordError / CorruptedVaultError. */
  async unlock(password: string): Promise<void> {
    if (!envelope) throw new Error('No vault');
    const opened = await openVault(envelope, password);
    enterUnlocked(envelope, opened.dek, assertVaultData(opened.data));
  },

  /** Applies an immutable update and schedules an encrypted save. */
  update(fn: (data: VaultData) => VaultData): void {
    if (state.status !== 'unlocked') return;
    const next = fn(state.data);
    if (next === state.data) return;
    setState({ ...state, data: next });
    scheduleSave();
  },

  flush,

  /** F-VAULT-4: drops plaintext and key from memory. */
  async lock(): Promise<void> {
    if (state.status !== 'unlocked') return;
    await flush();
    dek = null;
    stopAutoLock();
    setState({ status: 'locked' });
  },

  /** F-VAULT-5. Throws WrongPasswordError if the current password is wrong. */
  async changePassword(current: string, next: string): Promise<void> {
    if (!envelope || !dek) throw new Error('Vault is locked');
    await openVault(envelope, current);
    await flush();
    envelope = await rewrapPassword(envelope, dek, next, { iterations });
    await saveEnvelope(envelope);
  },

  /** F-IO-1: the current envelope, with pending changes saved first. */
  async exportBackup(): Promise<Envelope> {
    unlockedData();
    await flush();
    if (!envelope) throw new Error('Vault is locked');
    return envelope;
  },

  /**
   * F-IO-2: replaces local data with a backup. The backup's password becomes the
   * vault password. Throws before touching local data if the backup cannot be opened.
   */
  async importBackup(backup: Envelope, password: string): Promise<void> {
    const opened = await openVault(backup, password);
    const data = assertVaultData(opened.data);
    clearTimeout(saveTimer);
    dirty = false;
    await saveChain;
    await saveEnvelope(backup);
    enterUnlocked(backup, opened.dek, data);
  },

  /** F-VAULT-6 */
  async wipe(): Promise<void> {
    clearTimeout(saveTimer);
    dirty = false;
    await saveChain;
    await clearAll();
    envelope = null;
    dek = null;
    stopAutoLock();
    setState({ status: 'empty' });
  },
};
