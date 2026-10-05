import { centsToInput } from './money';
import { TX_TYPE_LABEL, type VaultData } from './model';

function cell(value: string): string {
  // Neutralise spreadsheet formula injection, then quote.
  const safe = /^[=+\-@\t\r]/.test(value) ? `'${value}` : value;
  return /[",\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

/** Plain-text CSV with UTF-8 BOM so Excel detects the encoding (F-IO-3). */
export function toCSV(data: VaultData): string {
  const categories = new Map(data.categories.map((c) => [c.id, c.name]));
  const accounts = new Map(data.accounts.map((a) => [a.id, a.name]));
  const rows = [...data.transactions]
    .sort((a, b) => (a.date === b.date ? a.createdAt.localeCompare(b.createdAt) : a.date.localeCompare(b.date)))
    .map((t) =>
      [
        t.date,
        TX_TYPE_LABEL[t.type],
        centsToInput(t.amount),
        categories.get(t.categoryId) ?? '',
        accounts.get(t.accountId) ?? '',
        t.note,
      ]
        .map(cell)
        .join(','),
    );
  return '\uFEFF' + ['日期,类型,金额,分类,账户,备注', ...rows].join('\r\n') + '\r\n';
}
