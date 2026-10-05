import 'fake-indexeddb/auto';
import { beforeEach, describe, expect, it } from 'vitest';
import { addDays, todayISO } from '../core/dates';
import { addTransactions, upsertRecurring } from '../core/ledger';
import { MIN_ITERATIONS, WrongPasswordError } from '../crypto/vault-crypto';
import { loadEnvelope } from '../storage/idb';
import { session } from './session';

session.configure({ iterations: MIN_ITERATIONS });

function unlocked() {
  const s = session.getState();
  if (s.status !== 'unlocked') throw new Error(`expected unlocked, got ${s.status}`);
  return s;
}

describe('session', () => {
  beforeEach(async () => {
    await session.init();
    if (session.getState().status !== 'empty') {
      await session.lock();
      await session.wipe();
    }
  });

  it('creates, edits, locks and unlocks with persisted changes', async () => {
    expect(session.getState().status).toBe('empty');
    await session.create('pass-word-1');
    const { data } = unlocked();
    session.update((d) =>
      addTransactions(d, [
        { type: 'expense', amount: 3500, categoryId: d.categories[0]!.id, accountId: d.accounts[0]!.id, date: todayISO(), note: '午饭' },
      ]),
    );
    expect(unlocked().data.transactions).toHaveLength(data.transactions.length + 1);

    await session.lock();
    expect(session.getState()).toEqual({ status: 'locked' });
    expect(JSON.stringify(await loadEnvelope())).not.toContain('午饭');

    await session.init();
    await expect(session.unlock('wrong-pass')).rejects.toBeInstanceOf(WrongPasswordError);
    await session.unlock('pass-word-1');
    expect(unlocked().data.transactions.map((t) => t.note)).toEqual(['午饭']);
  });

  it('applies recurring rules on unlock (F-REC-2)', async () => {
    await session.create('pass-word-1');
    session.update((d) =>
      upsertRecurring(d, {
        id: 'r1', name: '房租', type: 'expense', amount: 450000,
        categoryId: d.categories[0]!.id, accountId: d.accounts[0]!.id, note: '',
        frequency: 'weekly', interval: 1, startDate: addDays(todayISO(), -14), active: true,
      }),
    );
    await session.lock();
    await session.unlock('pass-word-1');
    expect(unlocked().recurringCreated).toBe(3);
    await session.lock();
    await session.unlock('pass-word-1');
    expect(unlocked().recurringCreated).toBe(0);
    expect(unlocked().data.transactions).toHaveLength(3);
  });

  it('changes password (F-VAULT-5)', async () => {
    await session.create('pass-word-1');
    await expect(session.changePassword('nope-nope', 'pass-word-2')).rejects.toBeInstanceOf(WrongPasswordError);
    await session.changePassword('pass-word-1', 'pass-word-2');
    await session.lock();
    await expect(session.unlock('pass-word-1')).rejects.toBeInstanceOf(WrongPasswordError);
    await session.unlock('pass-word-2');
    expect(session.getState().status).toBe('unlocked');
  });

  it('exports and imports a backup (F-IO-1, F-IO-2)', async () => {
    await session.create('pass-word-1');
    session.update((d) => ({ ...d, settings: { autoLockMinutes: 15 } }));
    const backup = await session.exportBackup();
    await session.lock();
    await session.wipe();

    await session.create('other-pass');
    await expect(session.importBackup(backup, 'other-pass')).rejects.toBeInstanceOf(WrongPasswordError);
    expect(unlocked().data.settings.autoLockMinutes).toBe(5);
    await session.importBackup(backup, 'pass-word-1');
    expect(unlocked().data.settings.autoLockMinutes).toBe(15);
    await session.lock();
    await session.unlock('pass-word-1');
    expect(unlocked().data.settings.autoLockMinutes).toBe(15);
  });
});
