import { describe, expect, it } from 'vitest';
import fixture from '../../fixtures/merge-cases.json';
import { createDefaultVault } from './defaults';
import { addTransactions, deleteTransaction, updateTransaction } from './ledger';
import { mergeVaults } from './merge';
import type { VaultData } from './model';

/** Fills the fields the fixture omits (see fixture description). */
function complete(partial: object): VaultData {
  return {
    schemaVersion: 1,
    accounts: [],
    categories: [],
    transactions: [],
    recurring: [],
    settings: { autoLockMinutes: 5 },
    deletions: [],
    ...partial,
  } as VaultData;
}

describe('mergeVaults — fixtures/merge-cases.json (F-SYNC-4)', () => {
  for (const c of fixture.cases) {
    it(c.name, () => {
      expect(complete(mergeVaults(complete(c.base), complete(c.other)))).toEqual(complete(c.expected));
    });
  }
});

const sortById = <T extends { id: string }>(xs: T[] | undefined) =>
  [...(xs ?? [])].sort((a, b) => a.id.localeCompare(b.id));

function canonical(d: VaultData) {
  return {
    ...d,
    accounts: sortById(d.accounts),
    categories: sortById(d.categories),
    transactions: sortById(d.transactions),
    recurring: sortById(d.recurring),
    deletions: sortById(d.deletions),
  };
}

describe('mergeVaults properties', () => {
  const t0 = new Date('2026-10-01T00:00:00Z');
  const t1 = new Date('2026-10-02T00:00:00Z');
  const t2 = new Date('2026-10-03T00:00:00Z');

  function diverged() {
    const vault = createDefaultVault();
    const input = (note: string) => ({
      type: 'expense' as const,
      amount: 1000,
      categoryId: vault.categories[0]!.id,
      accountId: vault.accounts[0]!.id,
      date: '2026-10-01',
      note,
    });
    const common = addTransactions(vault, [input('共同一'), input('共同二')], t0);
    const [first, second] = common.transactions;
    const remote = deleteTransaction(addTransactions(common, [input('远端新增')], t1), first!.id, t1);
    const local = updateTransaction(addTransactions(common, [input('本机新增')], t1), second!.id, { amount: 1, note: '本机改' }, t2);
    return { remote, local, firstId: first!.id, secondId: second!.id };
  }

  it('combines independent edits from both devices', () => {
    const { remote, local, firstId, secondId } = diverged();
    const merged = mergeVaults(remote, local);
    const notes = merged.transactions.map((t) => t.note);
    expect(notes).toEqual(['本机改', '远端新增', '本机新增']);
    expect(merged.transactions.some((t) => t.id === firstId)).toBe(false);
    expect(merged.transactions.find((t) => t.id === secondId)!.amount).toBe(1);
    expect(merged.deletions).toEqual([{ id: firstId, deletedAt: t1.toISOString() }]);
  });

  it('produces the same content regardless of argument order', () => {
    const { remote, local } = diverged();
    expect(canonical(mergeVaults(remote, local))).toEqual(canonical(mergeVaults(local, remote)));
  });

  it('is idempotent and omits empty deletions', () => {
    const vault = createDefaultVault();
    const merged = mergeVaults(vault, vault);
    expect(merged).toEqual(vault);
    expect('deletions' in merged).toBe(false);
    const { remote, local } = diverged();
    const once = mergeVaults(remote, local);
    expect(mergeVaults(once, local)).toEqual(once);
    expect(mergeVaults(once, once)).toEqual(once);
  });
});
