import { monthKeyOf, type MonthKey } from './dates';
import type { Cents, ISODate, Transaction, TxType, VaultData } from './model';

export interface Summary {
  income: Cents;
  expense: Cents;
  net: Cents;
}

export function transactionsInMonth(txs: Transaction[], month: MonthKey): Transaction[] {
  return txs.filter((t) => monthKeyOf(t.date) === month);
}

export function summarize(txs: Transaction[]): Summary {
  let income = 0;
  let expense = 0;
  for (const t of txs) {
    if (t.type === 'income') income += t.amount;
    else expense += t.amount;
  }
  return { income, expense, net: income - expense };
}

export interface CategoryTotal {
  categoryId: string;
  total: Cents;
  count: number;
  /** Share of the type's total, 0..1 */
  ratio: number;
}

export function totalsByCategory(txs: Transaction[], type: TxType): CategoryTotal[] {
  const map = new Map<string, { total: number; count: number }>();
  let sum = 0;
  for (const t of txs) {
    if (t.type !== type) continue;
    const entry = map.get(t.categoryId) ?? { total: 0, count: 0 };
    entry.total += t.amount;
    entry.count += 1;
    map.set(t.categoryId, entry);
    sum += t.amount;
  }
  return [...map.entries()]
    .map(([categoryId, { total, count }]) => ({
      categoryId,
      total,
      count,
      ratio: sum === 0 ? 0 : total / sum,
    }))
    .sort((a, b) => b.total - a.total);
}

export function accountBalances(data: VaultData): Map<string, Cents> {
  const balances = new Map<string, Cents>(data.accounts.map((a) => [a.id, a.initialBalance]));
  for (const t of data.transactions) {
    const current = balances.get(t.accountId) ?? 0;
    balances.set(t.accountId, current + (t.type === 'income' ? t.amount : -t.amount));
  }
  return balances;
}

export interface DayGroup {
  date: ISODate;
  items: Transaction[];
  summary: Summary;
}

/** Groups by date, newest day first; within a day, newest entry first (ties keep insertion order). */
export function groupByDate(txs: Transaction[]): DayGroup[] {
  const map = new Map<ISODate, Transaction[]>();
  for (const t of txs) {
    const list = map.get(t.date) ?? [];
    list.push(t);
    map.set(t.date, list);
  }
  return [...map.entries()]
    .sort(([a], [b]) => (a < b ? 1 : a > b ? -1 : 0))
    .map(([date, items]) => ({
      date,
      items: items.sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
      summary: summarize(items),
    }));
}
