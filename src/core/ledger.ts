import { addDays } from './dates';
import { newId } from './id';
import type {
  Account,
  Deletion,
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

/** Records a tombstone so sync merge drops the record on other devices too. */
function withDeletion(data: VaultData, id: string, now: Date): Deletion[] {
  const rest = (data.deletions ?? []).filter((d) => d.id !== id);
  return [...rest, { id, deletedAt: now.toISOString() }];
}

export function deleteTransaction(data: VaultData, id: string, now: Date = new Date()): VaultData {
  return {
    ...data,
    transactions: data.transactions.filter((t) => t.id !== id),
    deletions: withDeletion(data, id, now),
  };
}

function upsert<T extends { id: string; updatedAt?: string }>(list: T[], item: T, now: Date): T[] {
  const stamped = { ...item, updatedAt: now.toISOString() };
  return list.some((x) => x.id === item.id)
    ? list.map((x) => (x.id === item.id ? stamped : x))
    : [...list, stamped];
}

export function upsertAccount(data: VaultData, account: Account, now: Date = new Date()): VaultData {
  return { ...data, accounts: upsert(data.accounts, account, now) };
}

export function upsertCategory(data: VaultData, category: Category, now: Date = new Date()): VaultData {
  return { ...data, categories: upsert(data.categories, category, now) };
}

export function upsertRecurring(data: VaultData, rule: RecurringRule, now: Date = new Date()): VaultData {
  return { ...data, recurring: upsert(data.recurring, rule, now) };
}

/** Removes the rule only; transactions it generated are kept (F-REC-4). */
export function deleteRecurring(data: VaultData, id: string, now: Date = new Date()): VaultData {
  return {
    ...data,
    recurring: data.recurring.filter((r) => r.id !== id),
    deletions: withDeletion(data, id, now),
  };
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
  now: Date = new Date(),
): VaultData {
  const yesterday = addDays(today, -1);
  const updatedAt = now.toISOString();
  return {
    ...data,
    recurring: data.recurring.map((r) => {
      if (r.id !== id) return r;
      if (!active) return { ...r, active: false, updatedAt };
      const lastGenerated =
        r.lastGenerated && r.lastGenerated > yesterday ? r.lastGenerated : yesterday;
      return { ...r, active: true, lastGenerated, updatedAt };
    }),
  };
}

export function updateSettings(
  data: VaultData,
  patch: Partial<Settings>,
  now: Date = new Date(),
): VaultData {
  return { ...data, settings: { ...data.settings, ...patch, updatedAt: now.toISOString() } };
}
