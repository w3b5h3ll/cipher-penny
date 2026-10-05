import { addDays, addMonths, parseISODate } from './dates';
import { newId } from './id';
import type { ISODate, RecurringRule, Transaction, VaultData } from './model';

const MAX_OCCURRENCES_PER_RUN = 2000;

/** The n-th occurrence (0-based) of a rule, ignoring end date. */
export function nthOccurrence(rule: RecurringRule, n: number): ISODate {
  const step = Math.max(1, Math.floor(rule.interval)) * n;
  const anchorDay = parseISODate(rule.startDate).day;
  switch (rule.frequency) {
    case 'weekly':
      return addDays(rule.startDate, 7 * step);
    case 'monthly':
      return addMonths(rule.startDate, step, anchorDay);
    case 'yearly':
      return addMonths(rule.startDate, 12 * step, anchorDay);
  }
}

/** Occurrences in (afterExclusive, untilInclusive], respecting the rule's end date. */
export function occurrencesBetween(
  rule: RecurringRule,
  afterExclusive: ISODate | undefined,
  untilInclusive: ISODate,
): ISODate[] {
  const limit =
    rule.endDate && rule.endDate < untilInclusive ? rule.endDate : untilInclusive;
  const result: ISODate[] = [];
  for (let n = 0; n < MAX_OCCURRENCES_PER_RUN * 10; n++) {
    const date = nthOccurrence(rule, n);
    if (date > limit) break;
    if (!afterExclusive || date > afterExclusive) {
      result.push(date);
      if (result.length >= MAX_OCCURRENCES_PER_RUN) break;
    }
  }
  return result;
}

/** Next date this rule will produce a transaction on or after `today`, if any. */
export function nextOccurrence(rule: RecurringRule, today: ISODate): ISODate | undefined {
  const floor = rule.lastGenerated && rule.lastGenerated >= today ? rule.lastGenerated : addDays(today, -1);
  for (let n = 0; n < 100000; n++) {
    const date = nthOccurrence(rule, n);
    if (rule.endDate && date > rule.endDate) return undefined;
    if (date > floor) return date;
  }
  return undefined;
}

/**
 * Generates transactions for every active rule up to and including `today` (F-REC-2).
 * Idempotent: never creates two transactions for the same rule and date (F-REC-5).
 * Returns the original object when nothing changed.
 */
export function applyRecurring(
  data: VaultData,
  today: ISODate,
  now: Date = new Date(),
): { data: VaultData; created: number } {
  const existing = new Set(
    data.transactions.filter((t) => t.recurringId).map((t) => `${t.recurringId}|${t.date}`),
  );
  const ts = now.toISOString();
  const newTxs: Transaction[] = [];
  let rulesChanged = false;

  const recurring = data.recurring.map((rule) => {
    if (!rule.active) return rule;
    const dates = occurrencesBetween(rule, rule.lastGenerated, today);
    if (dates.length === 0) return rule;
    for (const date of dates) {
      const key = `${rule.id}|${date}`;
      if (existing.has(key)) continue;
      existing.add(key);
      newTxs.push({
        id: newId(),
        type: rule.type,
        amount: rule.amount,
        categoryId: rule.categoryId,
        accountId: rule.accountId,
        date,
        note: rule.note || rule.name,
        createdAt: ts,
        updatedAt: ts,
        recurringId: rule.id,
      });
    }
    rulesChanged = true;
    return { ...rule, lastGenerated: dates[dates.length - 1] };
  });

  if (!rulesChanged) return { data, created: 0 };
  return {
    data: { ...data, recurring, transactions: [...data.transactions, ...newTxs] },
    created: newTxs.length,
  };
}
