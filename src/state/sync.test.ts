import 'fake-indexeddb/auto';
import { beforeEach, describe, expect, it } from 'vitest';
import { todayISO } from '../core/dates';
import { addTransactions, deleteTransaction } from '../core/ledger';
import type { VaultData } from '../core/model';
import { assertVaultData } from '../core/validate';
import {
  changePassword,
  createVault,
  MIN_ITERATIONS,
  openVault,
  parseEnvelope,
  sealVault,
  WrongPasswordError,
} from '../crypto/vault-crypto';
import { RemoteError, type GitHubTarget, type RemoteFile } from '../remote/github';
import { loadSyncSecret } from '../storage/idb';
import { session, type SyncSetup } from './session';

/** In-memory stand-in for one file in a GitHub repo. */
class FakeRemote {
  file: RemoteFile | null = null;
  writes = 0;
  isPrivate = true;
  targets: GitHubTarget[] = [];
  /** Runs once just before the next write, to simulate another device pushing first. */
  beforeWrite: (() => void) | null = null;
  private counter = 0;

  nextSha() {
    return `sha-${++this.counter}`;
  }

  async check() {
    if (!this.isPrivate) throw new RemoteError('public-repo', '这是公开仓库');
  }

  async read() {
    return this.file ? { ...this.file } : null;
  }

  async write(text: string, sha: string | null) {
    const hook = this.beforeWrite;
    this.beforeWrite = null;
    hook?.();
    if ((this.file?.sha ?? null) !== sha) throw new RemoteError('conflict', 'stale');
    this.writes++;
    this.file = { sha: this.nextSha(), text };
    return this.file.sha;
  }
}

let fake = new FakeRemote();
session.configure({
  iterations: MIN_ITERATIONS,
  remote: (target) => {
    fake.targets.push(target);
    return { check: () => fake.check(), read: () => fake.read(), write: (t, s) => fake.write(t, s) };
  },
});

const PASSWORD = 'pass-word-1';
const setup: SyncSetup = { repo: 'paul/cipher-penny-data', path: '', token: 'github_pat_secret' };

function unlocked() {
  const s = session.getState();
  if (s.status !== 'unlocked') throw new Error(`expected unlocked, got ${s.status}`);
  return s;
}

function syncView() {
  const view = unlocked().sync;
  if (!view.configured) throw new Error('sync not configured');
  return view;
}

function expense(d: VaultData, note: string) {
  return addTransactions(d, [
    { type: 'expense', amount: 1000, categoryId: d.categories[0]!.id, accountId: d.accounts[0]!.id, date: todayISO(), note },
  ]);
}

async function readRemote(password = PASSWORD) {
  const envelope = parseEnvelope(JSON.parse(fake.file!.text));
  const opened = await openVault(envelope, password);
  return { envelope, dek: opened.dek, data: assertVaultData(opened.data) };
}

/** Prepares what another device would push after editing the remote vault. */
async function otherDevicePush(edit: (d: VaultData) => VaultData): Promise<RemoteFile> {
  const { envelope, dek, data } = await readRemote();
  const sealed = await sealVault(envelope, dek, edit(data));
  return { sha: fake.nextSha(), text: JSON.stringify(sealed) };
}

const notes = (d: VaultData) => d.transactions.map((t) => t.note).sort();

describe('sync (F-SYNC)', () => {
  beforeEach(async () => {
    fake = new FakeRemote();
    await session.init();
    if (session.getState().status !== 'empty') {
      await session.lock();
      await session.wipe();
    }
    await session.create(PASSWORD);
  });

  it('first sync pushes the local vault; an unchanged second sync does not write (F-SYNC-1, F-SYNC-2)', async () => {
    session.update((d) => expense(d, '午饭'));
    await session.connectSync(setup);
    expect(fake.targets[0]).toEqual({ owner: 'paul', repo: 'cipher-penny-data', path: 'vault.cpenny.json', token: 'github_pat_secret' });
    expect(fake.writes).toBe(1);
    expect(fake.file!.text).not.toContain('午饭');
    expect(notes((await readRemote()).data)).toEqual(['午饭']);
    expect(syncView()).toMatchObject({ repo: 'paul/cipher-penny-data', error: null, syncing: false });
    expect(syncView().lastSyncedAt).not.toBeNull();

    await session.syncNow();
    expect(fake.writes).toBe(1);
  });

  it('pushes local edits made after the last sync', async () => {
    await session.connectSync(setup);
    session.update((d) => expense(d, '晚饭'));
    await session.syncNow();
    expect(fake.writes).toBe(2);
    expect(notes((await readRemote()).data)).toEqual(['晚饭']);
  });

  it('merges edits from another device with local ones (F-SYNC-4)', async () => {
    session.update((d) => expense(d, '共同'));
    await session.connectSync(setup);
    const shared = unlocked().data.transactions[0]!.id;
    fake.file = await otherDevicePush((d) => deleteTransaction(expense(d, '远端'), shared));
    session.update((d) => expense(d, '本机'));
    await session.syncNow();

    expect(notes(unlocked().data)).toEqual(['本机', '远端']);
    expect(notes((await readRemote()).data)).toEqual(['本机', '远端']);
    await session.lock();
    await session.unlock(PASSWORD);
    expect(notes(unlocked().data)).toEqual(['本机', '远端']);
  });

  it('pulls without writing when only the remote changed', async () => {
    await session.connectSync(setup);
    fake.file = await otherDevicePush((d) => expense(d, '远端'));
    await session.syncNow();
    expect(fake.writes).toBe(1);
    expect(notes(unlocked().data)).toEqual(['远端']);
    await session.syncNow();
    expect(fake.writes).toBe(1);
  });

  it('retries when another device pushes between read and write', async () => {
    await session.connectSync(setup);
    const concurrent = await otherDevicePush((d) => expense(d, '远端'));
    fake.beforeWrite = () => {
      fake.file = concurrent;
    };
    session.update((d) => expense(d, '本机'));
    await session.syncNow();
    expect(syncView().error).toBeNull();
    expect(notes((await readRemote()).data)).toEqual(['本机', '远端']);
    expect(notes(unlocked().data)).toEqual(['本机', '远端']);
  });

  it('stops on a remote file from another vault and can overwrite it (F-SYNC-7)', async () => {
    const foreign = await createVault(PASSWORD, { schemaVersion: 1 }, { iterations: MIN_ITERATIONS });
    fake.file = { sha: 'foreign', text: JSON.stringify(foreign.envelope) };
    session.update((d) => expense(d, '本机'));
    await session.connectSync(setup);
    expect(syncView()).toMatchObject({ foreign: true });
    expect(syncView().error).toContain('另一个账本');
    expect(fake.writes).toBe(0);

    await session.overwriteRemote();
    expect(syncView()).toMatchObject({ foreign: false, error: null });
    expect(notes((await readRemote()).data)).toEqual(['本机']);
  });

  it('propagates a password change in both directions (F-SYNC-5)', async () => {
    await session.connectSync(setup);
    const { envelope, dek } = await readRemote();
    const rewrapped = await changePassword(envelope, dek, 'remote-new-pass', { iterations: MIN_ITERATIONS });
    fake.file = { sha: fake.nextSha(), text: JSON.stringify(rewrapped) };
    await session.syncNow();
    await session.lock();
    await expect(session.unlock(PASSWORD)).rejects.toBeInstanceOf(WrongPasswordError);
    await session.unlock('remote-new-pass');

    await session.changePassword('remote-new-pass', 'local-new-pass');
    await session.syncNow();
    await expect(readRemote('remote-new-pass')).rejects.toBeInstanceOf(WrongPasswordError);
    await readRemote('local-new-pass');
  });

  it('restores a new device from the remote vault (F-SYNC-6)', async () => {
    session.update((d) => expense(d, '午饭'));
    await session.connectSync(setup);
    await session.lock();
    await session.wipe();

    await expect(session.restoreFromRemote(setup, 'wrong-pass')).rejects.toBeInstanceOf(WrongPasswordError);
    expect(session.getState().status).toBe('empty');
    await session.restoreFromRemote(setup, PASSWORD);
    expect(notes(unlocked().data)).toEqual(['午饭']);
    expect(syncView().repo).toBe('paul/cipher-penny-data');
    await session.syncNow();
    expect(fake.writes).toBe(1);
  });

  it('pushes pending changes before locking', async () => {
    await session.connectSync(setup);
    session.update((d) => expense(d, '锁定前'));
    await session.lock();
    expect(notes((await readRemote()).data)).toEqual(['锁定前']);
  });

  it('refuses public repos and invalid input (F-SYNC-1)', async () => {
    fake.isPrivate = false;
    await expect(session.connectSync(setup)).rejects.toMatchObject({ kind: 'public-repo' });
    expect(unlocked().sync.configured).toBe(false);
    await expect(session.connectSync({ ...setup, repo: 'nope' })).rejects.toThrow('owner/repo');
    await expect(session.connectSync({ ...setup, path: '../x' })).rejects.toThrow('路径');
  });

  it('keeps the token out of backups and stores it encrypted; disconnect forgets it (F-SYNC-8)', async () => {
    await session.connectSync(setup);
    expect(JSON.stringify(await session.exportBackup())).not.toContain('github_pat_secret');
    expect(fake.file!.text).not.toContain('github_pat_secret');
    expect(JSON.stringify(await loadSyncSecret())).not.toContain('github_pat_secret');

    await session.lock();
    await session.unlock(PASSWORD);
    expect(syncView().repo).toBe('paul/cipher-penny-data');

    await session.disconnectSync();
    expect(unlocked().sync.configured).toBe(false);
    expect(await loadSyncSecret()).toBeNull();
    expect(fake.file).not.toBeNull();
  });
});
