import { todayISO } from '../core/dates';
import { createDefaultVault } from '../core/defaults';
import { mergeVaults } from '../core/merge';
import type { VaultData } from '../core/model';
import { applyRecurring } from '../core/recurring';
import { assertVaultData } from '../core/validate';
import {
  changePassword as rewrapPassword,
  createVault,
  decryptLocalSecret,
  DEFAULT_ITERATIONS,
  encryptLocalSecret,
  openVault,
  parseEnvelope,
  sealVault,
  UnsupportedFormatError,
  type Envelope,
} from '../crypto/vault-crypto';
import {
  checkRepo,
  normalizePath,
  parseRepo,
  readFile,
  writeFile,
  type GitHubTarget,
} from '../remote/github';
import {
  clearAll,
  deleteSyncSecret,
  loadEnvelope,
  loadSyncSecret,
  requestPersistentStorage,
  saveEnvelope,
  saveSyncSecret,
} from '../storage/idb';
import { ForeignVaultError, serializeEnvelope, syncOnce, type RemoteStore, type SyncCursor, type SyncResult } from './sync';

// The UI's only window into crypto/: error types and backup-file validation.
export {
  CorruptedVaultError,
  parseEnvelope,
  UnsupportedFormatError,
  WrongPasswordError,
  type Envelope,
} from '../crypto/vault-crypto';

export const DEFAULT_SYNC_PATH = 'vault.cpenny.json';

export type SyncView =
  | { configured: false }
  | {
      configured: true;
      repo: string;
      path: string;
      syncing: boolean;
      lastSyncedAt: string | null;
      error: string | null;
      /** The remote file belongs to another vault (F-SYNC-7). */
      foreign: boolean;
    };

export type SessionState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'empty' }
  | { status: 'locked' }
  | { status: 'unlocked'; data: VaultData; recurringCreated: number; saveError?: string; sync: SyncView };

/** What the user types to set up sync (F-SYNC-1, F-SYNC-6). */
export interface SyncSetup {
  repo: string;
  path: string;
  token: string;
}

interface SyncRecord {
  target: GitHubTarget;
  cursor: SyncCursor;
  lastSyncedAt: string | null;
}

type Remote = RemoteStore & { check(): Promise<void> };

const SAVE_DEBOUNCE_MS = 300;
const SYNC_DEBOUNCE_MS = 10_000;
const LOCK_SYNC_WAIT_MS = 5_000;
const AUTO_LOCK_CHECK_MS = 10_000;

function githubRemote(target: GitHubTarget): Remote {
  return {
    check: () => checkRepo(target),
    read: () => readFile(target),
    write: (text, sha) => writeFile(target, text, sha),
  };
}

let iterations = DEFAULT_ITERATIONS;
let remoteFor: (target: GitHubTarget) => Remote = githubRemote;
let state: SessionState = { status: 'loading' };
const listeners = new Set<() => void>();

// Secrets live only in these closures, and only while unlocked (F-VAULT-4, F-SYNC-8).
let envelope: Envelope | null = null;
let dek: CryptoKey | null = null;
let syncRecord: SyncRecord | null = null;

let dirty = false;
let saveTimer: ReturnType<typeof setTimeout> | undefined;
let saveChain: Promise<void> = Promise.resolve();
let lastActivity = Date.now();
let autoLockTimer: ReturnType<typeof setInterval> | undefined;

let syncTimer: ReturnType<typeof setTimeout> | undefined;
let syncPending = false;
let syncRunning: Promise<void> | null = null;
let syncAgain = false;
let syncStatus = { syncing: false, error: null as string | null, foreign: false };

function setState(next: SessionState) {
  state = next;
  for (const l of listeners) l();
}

function unlockedData(): VaultData {
  if (state.status !== 'unlocked') throw new Error('Vault is locked');
  return state.data;
}

function errorText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

async function persist(): Promise<void> {
  if (!dirty || !envelope || !dek || state.status !== 'unlocked') return;
  dirty = false;
  const data = state.data;
  try {
    envelope = await sealVault(envelope, dek, data);
    await saveEnvelope(envelope);
    if (state.status === 'unlocked' && state.saveError) setState({ ...state, saveError: undefined });
    scheduleSync();
  } catch (err) {
    dirty = true;
    if (state.status === 'unlocked') setState({ ...state, saveError: errorText(err) });
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

// ---- Sync (F-SYNC) ----

function syncView(): SyncView {
  if (!syncRecord) return { configured: false };
  const { owner, repo, path } = syncRecord.target;
  return { configured: true, repo: `${owner}/${repo}`, path, lastSyncedAt: syncRecord.lastSyncedAt, ...syncStatus };
}

function publishSync() {
  if (state.status === 'unlocked') setState({ ...state, sync: syncView() });
}

function resetSyncStatus() {
  syncStatus = { syncing: false, error: null, foreign: false };
}

function cancelScheduledSync() {
  clearTimeout(syncTimer);
  syncPending = false;
}

function scheduleSync() {
  if (!syncRecord) return;
  clearTimeout(syncTimer);
  syncPending = true;
  syncTimer = setTimeout(() => void requestSync(), SYNC_DEBOUNCE_MS);
}

async function storeSyncRecord(key: CryptoKey, record: SyncRecord): Promise<void> {
  await saveSyncSecret(await encryptLocalSecret(key, record));
}

/** Null if absent, or if it was written under another DEK (e.g. after importing a backup). */
async function loadSyncRecord(key: CryptoKey): Promise<SyncRecord | null> {
  const blob = await loadSyncSecret();
  if (!blob) return null;
  try {
    const record = (await decryptLocalSecret(key, blob)) as SyncRecord;
    if (typeof record?.target?.token !== 'string' || typeof record.cursor !== 'object') throw new Error('invalid');
    return record;
  } catch {
    await deleteSyncSecret();
    return null;
  }
}

function toTarget(setup: SyncSetup): GitHubTarget {
  const repo = parseRepo(setup.repo);
  if (!repo) throw new Error('仓库格式应为 owner/repo');
  const path = normalizePath(setup.path || DEFAULT_SYNC_PATH);
  if (!path) throw new Error('文件路径无效');
  const token = setup.token.trim();
  if (!token) throw new Error('请填写 GitHub 令牌');
  return { ...repo, path, token };
}

function freshCursor(): SyncCursor {
  return { remoteSha: null, localPayloadIv: null, keyChanged: false };
}

/** Runs sync rounds one at a time; a request during a round queues one more round. */
function requestSync(): Promise<void> {
  cancelScheduledSync();
  if (!syncRecord || state.status !== 'unlocked') return Promise.resolve();
  if (syncRunning) {
    syncAgain = true;
    return syncRunning;
  }
  syncRunning = (async () => {
    try {
      do {
        syncAgain = false;
        await syncRound();
      } while (syncAgain && syncRecord && state.status === 'unlocked');
    } finally {
      syncRunning = null;
    }
  })();
  return syncRunning;
}

async function syncRound(): Promise<void> {
  await flush();
  cancelScheduledSync();
  const record = syncRecord;
  const key = dek;
  const env = envelope;
  if (!record || !key || !env || state.status !== 'unlocked') return;
  const snapshot = state.data;
  syncStatus = { ...syncStatus, syncing: true };
  publishSync();
  try {
    const result = await syncOnce({ remote: remoteFor(record.target), envelope: env, data: snapshot, dek: key, cursor: record.cursor });
    // Locked, wiped, disconnected or password changed meanwhile: the next round redoes it.
    if (dek !== key || syncRecord !== record) return;
    if (result.kind === 'merged') await adoptMerged(result, snapshot);
    const localPayloadIv = result.kind === 'unchanged' ? record.cursor.localPayloadIv : result.envelope.payload.iv;
    syncRecord = {
      ...record,
      cursor: { remoteSha: result.remoteSha, localPayloadIv, keyChanged: false },
      lastSyncedAt: new Date().toISOString(),
    };
    resetSyncStatus();
    await storeSyncRecord(key, syncRecord);
  } catch (err) {
    syncStatus = { syncing: false, error: errorText(err), foreign: err instanceof ForeignVaultError };
  } finally {
    syncStatus = { ...syncStatus, syncing: false };
    publishSync();
  }
}

/** Takes the merged vault as the local copy, keeping edits made while the sync ran. */
function adoptMerged(result: Extract<SyncResult, { kind: 'merged' }>, snapshot: VaultData): Promise<void> {
  saveChain = saveChain.then(async () => {
    envelope = result.envelope;
    await saveEnvelope(result.envelope);
    if (state.status !== 'unlocked') return;
    if (state.data === snapshot) {
      setState({ ...state, data: result.data });
    } else {
      setState({ ...state, data: mergeVaults(result.data, state.data) });
      scheduleSave();
    }
  });
  return saveChain;
}

// ---- Lifecycle ----

function enterUnlocked(env: Envelope, key: CryptoKey, data: VaultData, record: SyncRecord | null) {
  envelope = env;
  dek = key;
  syncRecord = record;
  resetSyncStatus();
  setState({ status: 'unlocked', data, recurringCreated: 0, sync: syncView() });
  startBackgroundTasks();
  // Pull first so another device's back-fill or deletions are seen before we back-fill.
  if (syncRecord) void requestSync().finally(fillRecurring);
  else fillRecurring();
}

function fillRecurring() {
  if (state.status !== 'unlocked') return;
  const { data, created } = applyRecurring(state.data, todayISO());
  if (created === 0) return;
  setState({ ...state, data, recurringCreated: created });
  scheduleSave();
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
  if (document.visibilityState === 'hidden') {
    void flush().then(() => (syncPending ? requestSync() : undefined));
  } else {
    checkAutoLock();
    void requestSync();
  }
}

function onPageHide() {
  void flush();
}

function onOnline() {
  void requestSync();
}

function startBackgroundTasks() {
  lastActivity = Date.now();
  if (typeof window === 'undefined' || autoLockTimer) return;
  for (const ev of ['pointerdown', 'keydown', 'wheel', 'touchstart'] as const) {
    window.addEventListener(ev, onActivity, { passive: true });
  }
  document.addEventListener('visibilitychange', onVisibilityChange);
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('online', onOnline);
  autoLockTimer = setInterval(checkAutoLock, AUTO_LOCK_CHECK_MS);
}

function stopBackgroundTasks() {
  cancelScheduledSync();
  if (typeof window === 'undefined' || !autoLockTimer) return;
  for (const ev of ['pointerdown', 'keydown', 'wheel', 'touchstart'] as const) {
    window.removeEventListener(ev, onActivity);
  }
  document.removeEventListener('visibilitychange', onVisibilityChange);
  window.removeEventListener('pagehide', onPageHide);
  window.removeEventListener('online', onOnline);
  clearInterval(autoLockTimer);
  autoLockTimer = undefined;
}

function dropSecrets() {
  dek = null;
  syncRecord = null;
  resetSyncStatus();
}

export const session = {
  getState: (): SessionState => state,

  subscribe(listener: () => void): () => void {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },

  /** For tests only: lower the KDF cost and replace GitHub with a fake. */
  configure(options: { iterations?: number; remote?: (target: GitHubTarget) => Remote }) {
    if (options.iterations !== undefined) iterations = options.iterations;
    if (options.remote) remoteFor = options.remote;
  },

  async init(): Promise<void> {
    try {
      envelope = await loadEnvelope();
      setState({ status: envelope ? 'locked' : 'empty' });
    } catch (err) {
      setState({ status: 'error', message: errorText(err) });
    }
  },

  /** F-VAULT-1 */
  async create(password: string): Promise<void> {
    const data = createDefaultVault();
    const created = await createVault(password, data, { iterations });
    await deleteSyncSecret();
    await saveEnvelope(created.envelope);
    void requestPersistentStorage();
    enterUnlocked(created.envelope, created.dek, data, null);
  },

  /** F-VAULT-2. Throws WrongPasswordError / CorruptedVaultError. */
  async unlock(password: string): Promise<void> {
    if (!envelope) throw new Error('No vault');
    const opened = await openVault(envelope, password);
    const data = assertVaultData(opened.data);
    enterUnlocked(envelope, opened.dek, data, await loadSyncRecord(opened.dek));
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

  /** F-VAULT-4: drops plaintext, key and sync token from memory. */
  async lock(): Promise<void> {
    if (state.status !== 'unlocked') return;
    await flush();
    if (syncPending || syncRunning) {
      await Promise.race([requestSync(), new Promise((r) => setTimeout(r, LOCK_SYNC_WAIT_MS))]);
    }
    stopBackgroundTasks();
    dropSecrets();
    setState({ status: 'locked' });
  },

  /** F-VAULT-5. Throws WrongPasswordError if the current password is wrong. */
  async changePassword(current: string, next: string): Promise<void> {
    if (!envelope || !dek) throw new Error('Vault is locked');
    await openVault(envelope, current);
    await flush();
    envelope = await rewrapPassword(envelope, dek, next, { iterations });
    await saveEnvelope(envelope);
    if (syncRecord) {
      syncRecord = { ...syncRecord, cursor: { ...syncRecord.cursor, keyChanged: true } };
      await storeSyncRecord(dek, syncRecord);
      void requestSync();
    }
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
    await syncRunning;
    stopBackgroundTasks();
    await saveEnvelope(backup);
    // Same vault: merge the backup into the remote copy instead of overwriting it.
    const record = await loadSyncRecord(opened.dek);
    const resumed = record ? { ...record, cursor: freshCursor() } : null;
    if (resumed) await storeSyncRecord(opened.dek, resumed);
    enterUnlocked(backup, opened.dek, data, resumed);
  },

  /** F-VAULT-6 */
  async wipe(): Promise<void> {
    clearTimeout(saveTimer);
    dirty = false;
    await saveChain;
    stopBackgroundTasks();
    await clearAll();
    envelope = null;
    dropSecrets();
    setState({ status: 'empty' });
  },

  // ---- Sync (F-SYNC) ----

  /** F-SYNC-1. Throws (with a user-facing message) if the repo is unusable. */
  async connectSync(setup: SyncSetup): Promise<void> {
    if (!dek || state.status !== 'unlocked') throw new Error('Vault is locked');
    const target = toTarget(setup);
    await remoteFor(target).check();
    await syncRunning;
    syncRecord = { target, cursor: freshCursor(), lastSyncedAt: null };
    await storeSyncRecord(dek, syncRecord);
    resetSyncStatus();
    publishSync();
    await requestSync();
  },

  /** F-SYNC-3: manual “sync now”. */
  syncNow(): Promise<void> {
    return requestSync();
  },

  /** F-SYNC-8: forgets the local sync settings; the remote file is untouched. */
  async disconnectSync(): Promise<void> {
    cancelScheduledSync();
    syncRecord = null;
    await syncRunning;
    await deleteSyncSecret();
    resetSyncStatus();
    publishSync();
  },

  /** F-SYNC-7: replaces the remote file with the local vault. */
  async overwriteRemote(): Promise<void> {
    await syncRunning;
    const record = syncRecord;
    const key = dek;
    if (!record || !key) throw new Error('同步未开启');
    await flush();
    if (!envelope) throw new Error('Vault is locked');
    const local = envelope;
    const remote = remoteFor(record.target);
    const existing = await remote.read();
    const remoteSha = await remote.write(serializeEnvelope(local), existing?.sha ?? null);
    if (syncRecord !== record) return;
    syncRecord = {
      ...record,
      cursor: { remoteSha, localPayloadIv: local.payload.iv, keyChanged: false },
      lastSyncedAt: new Date().toISOString(),
    };
    await storeSyncRecord(key, syncRecord);
    resetSyncStatus();
    publishSync();
  },

  /**
   * F-SYNC-6: sets up this device from the remote vault. Throws WrongPasswordError,
   * or an error with a user-facing message, before touching local data.
   */
  async restoreFromRemote(setup: SyncSetup, password: string): Promise<void> {
    const target = toTarget(setup);
    const remote = remoteFor(target);
    await remote.check();
    const file = await remote.read();
    if (!file) throw new Error('仓库里还没有同步文件，请先在已有数据的设备上开启同步');
    let remoteEnvelope: Envelope;
    try {
      remoteEnvelope = parseEnvelope(JSON.parse(file.text));
    } catch (err) {
      throw err instanceof UnsupportedFormatError ? err : new UnsupportedFormatError('同步文件不是有效的 CipherPenny 账本');
    }
    const opened = await openVault(remoteEnvelope, password);
    const data = assertVaultData(opened.data);
    await saveEnvelope(remoteEnvelope);
    const record: SyncRecord = {
      target,
      cursor: { remoteSha: file.sha, localPayloadIv: remoteEnvelope.payload.iv, keyChanged: false },
      lastSyncedAt: new Date().toISOString(),
    };
    await storeSyncRecord(opened.dek, record);
    void requestPersistentStorage();
    enterUnlocked(remoteEnvelope, opened.dek, data, record);
  },
};
