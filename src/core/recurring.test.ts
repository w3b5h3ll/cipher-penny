import { describe, expect, it } from 'vitest';
import { createDefaultVault } from './defaults';
import { setRecurringActive, upsertRecurring } from './ledger';
import type { RecurringRule, VaultData } from './model';
import { applyRecurring, nextOccurrence, occurrencesBetween } from './recurring';

function rule(overrides: Partial<RecurringRule>): RecurringRule {
  return {
    id: 'r1',
    name: 'iCloud',
    type: 'expense',
    amount: 2100,
    categoryId: 'c1',
    accountId: 'a1',
    note: '',
    frequency: 'monthly',
    interval: 1,
    startDate: '2026-01-31',
    active: true,
    ...overrides,
  };
}

function vaultWith(r: RecurringRule): VaultData {
  return upsertRecurring(createDefaultVault(), r);
}

describe('occurrencesBetween (F-REC-1, F-REC-3)', () => {
  it('clamps monthly rules to month end and returns to the anchor day', () => {
    expect(occurrencesBetween(rule({}), undefined, '2026-05-01')).toEqual([
      '2026-01-31',
      '2026-02-28',
      '2026-03-31',
      '2026-04-30',
    ]);
  });

  it('handles weekly rules with an interval', () => {
    const r = rule({ frequency: 'weekly', interval: 2, startDate: '2026-09-07' });
    expect(occurrencesBetween(r, undefined, '2026-10-05')).toEqual(['2026-09-07', '2026-09-21', '2026-10-05']);
  });

  it('maps Feb 29 yearly rules to Feb 28 in common years', () => {
    const r = rule({ frequency: 'yearly', startDate: '2028-02-29' });
    expect(occurrencesBetween(r, undefined, '2033-01-01')).toEqual([
      '2028-02-29',
      '2029-02-28',
      '2030-02-28',
      '2031-02-28',
      '2032-02-29',
    ]);
  });

  it('respects the exclusive lower bound and the end date', () => {
    const r = rule({ startDate: '2026-01-15', endDate: '2026-04-14' });
    expect(occurrencesBetween(r, '2026-01-15', '2026-12-31')).toEqual(['2026-02-15', '2026-03-15']);
  });
});

describe('applyRecurring (F-REC-2, F-REC-5)', () => {
  it('back-fills up to and including today', () => {
    const { data, created } = applyRecurring(vaultWith(rule({ startDate: '2026-08-05' })), '2026-10-05');
    expect(created).toBe(3);
    expect(data.transactions.map((t) => t.date)).toEqual(['2026-08-05', '2026-09-05', '2026-10-05']);
    expect(data.transactions.every((t) => t.recurringId === 'r1' && t.amount === 2100)).toBe(true);
    expect(data.transactions[0]!.note).toBe('iCloud');
    expect(data.recurring[0]!.lastGenerated).toBe('2026-10-05');
  });

  it('is idempotent', () => {
    const first = applyRecurring(vaultWith(rule({ startDate: '2026-08-05' })), '2026-10-05').data;
    const second = applyRecurring(first, '2026-10-05');
    expect(second.created).toBe(0);
    expect(second.data).toBe(first);
  });

  it('uses deterministic ids and the occurrence date as updatedAt (vault-format §3)', () => {
    const { data } = applyRecurring(
      vaultWith(rule({ startDate: '2026-10-05' })),
      '2026-10-05',
      new Date('2026-10-07T12:00:00Z'),
    );
    const tx = data.transactions[0]!;
    expect(tx.id).toBe('r1:2026-10-05');
    expect(tx.createdAt).toBe('2026-10-07T12:00:00.000Z');
    expect(tx.updatedAt).toBe(new Date(2026, 9, 5).toISOString());
  });

  it('does not duplicate when lastGenerated was lost', () => {
    const first = applyRecurring(vaultWith(rule({ startDate: '2026-08-05' })), '2026-10-05').data;
    const reset: VaultData = { ...first, recurring: first.recurring.map((r) => ({ ...r, lastGenerated: undefined })) };
    expect(applyRecurring(reset, '2026-10-05').created).toBe(0);
  });

  it('skips inactive rules and rules starting in the future', () => {
    expect(applyRecurring(vaultWith(rule({ active: false, startDate: '2026-01-01' })), '2026-10-05').created).toBe(0);
    expect(applyRecurring(vaultWith(rule({ startDate: '2026-11-01' })), '2026-10-05').created).toBe(0);
  });

  it('does not back-fill the paused period after resuming (F-REC-4)', () => {
    let data = applyRecurring(vaultWith(rule({ startDate: '2026-06-10' })), '2026-07-10').data;
    data = setRecurringActive(data, 'r1', false, '2026-07-11');
    data = setRecurringActive(data, 'r1', true, '2026-10-05');
    const result = applyRecurring(data, '2026-10-10');
    expect(result.data.transactions.map((t) => t.date)).toEqual(['2026-06-10', '2026-07-10', '2026-10-10']);
  });
});

describe('nextOccurrence', () => {
  it('returns today if due and not yet generated, otherwise the following one', () => {
    expect(nextOccurrence(rule({ startDate: '2026-01-05' }), '2026-10-05')).toBe('2026-10-05');
    expect(nextOccurrence(rule({ startDate: '2026-01-05', lastGenerated: '2026-10-05' }), '2026-10-05')).toBe('2026-11-05');
    expect(nextOccurrence(rule({ startDate: '2026-01-05', endDate: '2026-09-30' }), '2026-10-05')).toBeUndefined();
  });
});
