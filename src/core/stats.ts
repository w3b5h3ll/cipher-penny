import { daysInMonth, monthKeyOf, type MonthKey } from './dates';
import type { Cents, ISODate, Transaction } from './model';

/** The app only tracks spending (spec §2); income records may exist in data but are never counted. */
export function expensesOf(txs: Transaction[]): Transaction[] {
  return txs.filter((t) => t.type === 'expense');
}

export function transactionsInMonth(txs: Transaction[], month: MonthKey): Transaction[] {
  return txs.filter((t) => monthKeyOf(t.date) === month);
}

export function transactionsInYear(txs: Transaction[], year: number): Transaction[] {
  const prefix = `${year}-`;
  return txs.filter((t) => t.date.startsWith(prefix));
}

export interface Spending {
  total: Cents;
  count: number;
}

export function spending(txs: Transaction[]): Spending {
  let total = 0;
  let count = 0;
  for (const t of expensesOf(txs)) {
    total += t.amount;
    count += 1;
  }
  return { total, count };
}

export interface MonthSpending extends Spending {
  month: MonthKey;
}

/** F-STAT-4: one entry per calendar month of `year`, January first, empty months included. */
export function monthlySpending(txs: Transaction[], year: number): MonthSpending[] {
  const byMonth = new Map<MonthKey, Transaction[]>();
  for (const t of transactionsInYear(txs, year)) {
    const key = monthKeyOf(t.date);
    const list = byMonth.get(key) ?? [];
    list.push(t);
    byMonth.set(key, list);
  }
  return Array.from({ length: 12 }, (_, i) => {
    const month = `${year}-${String(i + 1).padStart(2, '0')}`;
    return { month, ...spending(byMonth.get(month) ?? []) };
  });
}

/** Months of `year` that have started by `today`: 12 for past years, 0 for future ones. */
export function monthsElapsed(year: number, today: ISODate): number {
  const currentYear = Number(today.slice(0, 4));
  if (year < currentYear) return 12;
  if (year > currentYear) return 0;
  return Number(today.slice(5, 7));
}

/** Days of `month` that have started by `today`: the whole month if past, 0 if future. */
export function daysElapsed(month: MonthKey, today: ISODate): number {
  const current = monthKeyOf(today);
  if (month > current) return 0;
  if (month < current) return daysInMonth(Number(month.slice(0, 4)), Number(month.slice(5, 7)));
  return Number(today.slice(8, 10));
}

export interface GroupTotal {
  id: string;
  total: Cents;
  count: number;
  /** Share of total spending, 0..1 */
  ratio: number;
}

function spendingBy(txs: Transaction[], keyOf: (t: Transaction) => string): GroupTotal[] {
  const map = new Map<string, { total: number; count: number }>();
  let sum = 0;
  for (const t of expensesOf(txs)) {
    const key = keyOf(t);
    const entry = map.get(key) ?? { total: 0, count: 0 };
    entry.total += t.amount;
    entry.count += 1;
    map.set(key, entry);
    sum += t.amount;
  }
  return [...map.entries()]
    .map(([id, { total, count }]) => ({ id, total, count, ratio: sum === 0 ? 0 : total / sum }))
    .sort((a, b) => b.total - a.total);
}

/** F-STAT-2, largest first. */
export function spendingByCategory(txs: Transaction[]): GroupTotal[] {
  return spendingBy(txs, (t) => t.categoryId);
}

/** F-STAT-3, largest first. */
export function spendingByAccount(txs: Transaction[]): GroupTotal[] {
  return spendingBy(txs, (t) => t.accountId);
}

export interface DayGroup {
  date: ISODate;
  items: Transaction[];
  total: Cents;
}

/** Expenses grouped by date, newest day first; within a day, newest entry first (ties keep insertion order). */
export function groupByDate(txs: Transaction[]): DayGroup[] {
  const map = new Map<ISODate, Transaction[]>();
  for (const t of expensesOf(txs)) {
    const list = map.get(t.date) ?? [];
    list.push(t);
    map.set(t.date, list);
  }
  return [...map.entries()]
    .sort(([a], [b]) => (a < b ? 1 : a > b ? -1 : 0))
    .map(([date, items]) => ({
      date,
      items: items.sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
      total: spending(items).total,
    }));
}
