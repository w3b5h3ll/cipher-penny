import { addDays } from './dates';
import { newId } from './id';
import type {
  Account,
  Category,
  ISODate,
  RecurringRule,
  Settings,
  Transaction,
  TransactionInput,
  VaultData,
} from './model';

export function addTransactions(
  data: VaultData,
  inputs: TransactionInput[],
  now: Date = new Date(),
): VaultData {
  if (inputs.length === 0) return data;
  const ts = now.toISOString();
  const created: Transaction[] = inputs.map((input) => ({
    ...input,
    id: newId(),
    createdAt: ts,
    updatedAt: ts,
  }));
  return { ...data, transactions: [...data.transactions, ...created] };
}

export function updateTransaction(
  data: VaultData,
  id: string,
  patch: Partial<TransactionInput>,
  now: Date = new Date(),
): VaultData {
  return {
    ...data,
    transactions: data.transactions.map((t) =>
      t.id === id ? { ...t, ...patch, updatedAt: now.toISOString() } : t,
    ),
  };
}

export function deleteTransaction(data: VaultData, id: string): VaultData {
  return { ...data, transactions: data.transactions.filter((t) => t.id !== id) };
}

function upsert<T extends { id: string }>(list: T[], item: T): T[] {
  return list.some((x) => x.id === item.id)
    ? list.map((x) => (x.id === item.id ? item : x))
    : [...list, item];
}

export function upsertAccount(data: VaultData, account: Account): VaultData {
  return { ...data, accounts: upsert(data.accounts, account) };
}

export function upsertCategory(data: VaultData, category: Category): VaultData {
  return { ...data, categories: upsert(data.categories, category) };
}

export function upsertRecurring(data: VaultData, rule: RecurringRule): VaultData {
  return { ...data, recurring: upsert(data.recurring, rule) };
}

/** Removes the rule only; transactions it generated are kept (F-REC-4). */
export function deleteRecurring(data: VaultData, id: string): VaultData {
  return { ...data, recurring: data.recurring.filter((r) => r.id !== id) };
}

/**
 * Pauses or resumes a rule. Resuming skips occurrences that fell inside the paused
 * period, so a cancelled-then-restarted subscription is not back-filled (F-REC-4).
 */
export function setRecurringActive(
  data: VaultData,
  id: string,
  active: boolean,
  today: ISODate,
): VaultData {
  const yesterday = addDays(today, -1);
  return {
    ...data,
    recurring: data.recurring.map((r) => {
      if (r.id !== id) return r;
      if (!active) return { ...r, active: false };
      const lastGenerated =
        r.lastGenerated && r.lastGenerated > yesterday ? r.lastGenerated : yesterday;
      return { ...r, active: true, lastGenerated };
    }),
  };
}

export function updateSettings(data: VaultData, patch: Partial<Settings>): VaultData {
  return { ...data, settings: { ...data.settings, ...patch } };
}
