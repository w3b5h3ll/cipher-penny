import type { Deletion, RecurringRule, Transaction, VaultData } from './model';

/**
 * Record-level merge of two copies of the same vault (F-SYNC-4).
 * Normative rules: docs/vault-format.md §5.1. `base` is the remote copy, `other` the local one.
 */
export function mergeVaults(base: VaultData, other: VaultData): VaultData {
  const deletions = mergeDeletions(base.deletions ?? [], other.deletions ?? []);
  const deletedAt = new Map(deletions.map((d) => [d.id, d.deletedAt]));
  const alive = <T extends { id: string; updatedAt?: string }>(r: T) => {
    const at = deletedAt.get(r.id);
    return at === undefined || at < (r.updatedAt ?? '');
  };

  const extra = Object.fromEntries(Object.entries(other).filter(([key]) => !(key in base)));
  const merged: VaultData = {
    ...base,
    ...extra,
    accounts: mergeById(base.accounts, other.accounts, newer).filter(alive),
    categories: mergeById(base.categories, other.categories, newer).filter(alive),
    transactions: dedupeGenerated(
      mergeById(base.transactions, other.transactions, newer).filter(alive),
    ),
    recurring: mergeById(base.recurring, other.recurring, newerRule).filter(alive),
    settings: newer(base.settings, other.settings),
  };
  if (deletions.length > 0) merged.deletions = deletions;
  else delete merged.deletions;
  return merged;
}

/** Later `updatedAt` wins; ties are broken by serialized content so both sides agree. */
function newer<T extends { updatedAt?: string }>(a: T, b: T): T {
  const ua = a.updatedAt ?? '';
  const ub = b.updatedAt ?? '';
  if (ua !== ub) return ua > ub ? a : b;
  return JSON.stringify(a) >= JSON.stringify(b) ? a : b;
}

function newerRule(a: RecurringRule, b: RecurringRule): RecurringRule {
  const winner = newer(a, b);
  const lastGenerated = maxOptional(a.lastGenerated, b.lastGenerated);
  return winner.lastGenerated === lastGenerated ? winner : { ...winner, lastGenerated };
}

function maxOptional(a: string | undefined, b: string | undefined): string | undefined {
  if (a === undefined) return b;
  if (b === undefined) return a;
  return a > b ? a : b;
}

function mergeById<T extends { id: string }>(base: T[], other: T[], pick: (a: T, b: T) => T): T[] {
  const otherById = new Map(other.map((x) => [x.id, x]));
  const baseIds = new Set(base.map((x) => x.id));
  const result = base.map((b) => {
    const o = otherById.get(b.id);
    return o ? pick(b, o) : b;
  });
  for (const o of other) if (!baseIds.has(o.id)) result.push(o);
  return result;
}

function mergeDeletions(base: Deletion[], other: Deletion[]): Deletion[] {
  const byId = new Map<string, Deletion>();
  for (const d of [...base, ...other]) {
    const seen = byId.get(d.id);
    if (!seen || d.deletedAt > seen.deletedAt) byId.set(d.id, seen ? { ...seen, deletedAt: d.deletedAt } : d);
  }
  return [...byId.values()];
}

/** One transaction per (recurringId, date): latest `updatedAt`, then smallest id. */
function dedupeGenerated(txs: Transaction[]): Transaction[] {
  const keep = new Map<string, Transaction>();
  for (const tx of txs) {
    if (!tx.recurringId) continue;
    const key = `${tx.recurringId}|${tx.date}`;
    const kept = keep.get(key);
    if (!kept || tx.updatedAt > kept.updatedAt || (tx.updatedAt === kept.updatedAt && tx.id < kept.id)) {
      keep.set(key, tx);
    }
  }
  return txs.filter((tx) => !tx.recurringId || keep.get(`${tx.recurringId}|${tx.date}`) === tx);
}
