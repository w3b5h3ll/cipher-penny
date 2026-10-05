import { describe, expect, it } from 'vitest';
import { toCSV } from './csv';
import { createDefaultVault } from './defaults';
import { addTransactions, deleteTransaction, updateTransaction, upsertAccount } from './ledger';
import type { TransactionInput, VaultData } from './model';
import { accountBalances, groupByDate, summarize, totalsByCategory, transactionsInMonth } from './stats';

function setup(): { data: VaultData; food: string; transport: string; salary: string; cash: string; wechat: string } {
  const base = createDefaultVault();
  const id = (name: string) => base.categories.find((c) => c.name === name)!.id;
  const acc = (name: string) => base.accounts.find((a) => a.name === name)!.id;
  const food = id('餐饮');
  const transport = id('交通');
  const salary = id('工资');
  const cash = acc('现金');
  const wechat = acc('微信');
  const tx = (p: Partial<TransactionInput>): TransactionInput => ({
    type: 'expense',
    amount: 0,
    categoryId: food,
    accountId: cash,
    date: '2026-10-01',
    note: '',
    ...p,
  });
  const data = addTransactions(
    upsertAccount(base, { ...base.accounts[0]!, initialBalance: 10000 }),
    [
      tx({ amount: 3500, date: '2026-10-01' }),
      tx({ amount: 2800, categoryId: transport, accountId: wechat, date: '2026-10-02' }),
      tx({ amount: 1500, date: '2026-10-02', note: '=cmd()' }),
      tx({ type: 'income', amount: 800000, categoryId: salary, accountId: wechat, date: '2026-10-05' }),
      tx({ amount: 9900, date: '2026-09-30' }),
    ],
    new Date('2026-10-05T00:00:00Z'),
  );
  return { data, food, transport, salary, cash, wechat };
}

describe('stats (F-STAT)', () => {
  it('summarises a month', () => {
    const { data } = setup();
    const october = transactionsInMonth(data.transactions, '2026-10');
    expect(october).toHaveLength(4);
    expect(summarize(october)).toEqual({ income: 800000, expense: 7800, net: 792200 });
  });

  it('totals by category, largest first', () => {
    const { data, food, transport } = setup();
    const totals = totalsByCategory(transactionsInMonth(data.transactions, '2026-10'), 'expense');
    expect(totals.map((t) => [t.categoryId, t.total, t.count])).toEqual([
      [food, 5000, 2],
      [transport, 2800, 1],
    ]);
    expect(totals[0]!.ratio).toBeCloseTo(5000 / 7800);
  });

  it('computes account balances from initial balance', () => {
    const { data, cash, wechat } = setup();
    const balances = accountBalances(data);
    expect(balances.get(cash)).toBe(10000 - 3500 - 1500 - 9900);
    expect(balances.get(wechat)).toBe(800000 - 2800);
  });

  it('groups by date, newest first', () => {
    const { data } = setup();
    const groups = groupByDate(transactionsInMonth(data.transactions, '2026-10'));
    expect(groups.map((g) => g.date)).toEqual(['2026-10-05', '2026-10-02', '2026-10-01']);
    expect(groups[1]!.summary.expense).toBe(4300);
  });
});

describe('ledger (F-TX-1, F-TX-3)', () => {
  it('updates and deletes immutably', () => {
    const { data } = setup();
    const target = data.transactions[0]!;
    const updated = updateTransaction(data, target.id, { amount: 4000 }, new Date('2026-10-06T00:00:00Z'));
    expect(updated.transactions[0]!.amount).toBe(4000);
    expect(updated.transactions[0]!.updatedAt).toBe('2026-10-06T00:00:00.000Z');
    expect(data.transactions[0]!.amount).toBe(3500);
    expect(deleteTransaction(updated, target.id).transactions).toHaveLength(4);
  });
});

describe('toCSV (F-IO-3)', () => {
  it('exports sorted rows with BOM and neutralises formulas', () => {
    const { data } = setup();
    const csv = toCSV(data);
    expect(csv.startsWith('\uFEFF日期,类型,金额,分类,账户,备注\r\n')).toBe(true);
    const lines = csv.trim().split('\r\n');
    expect(lines[1]).toBe('2026-09-30,支出,99,餐饮,现金,');
    expect(csv).toContain(",'=cmd()");
    expect(lines).toHaveLength(6);
  });
});
