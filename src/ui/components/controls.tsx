import type { ReactNode } from 'react';
import { addMonthsToKey, formatMonthKey, type MonthKey } from '../../core/dates';
import type { Account, Category, TxType } from '../../core/model';

export function Field({ label, children, hint }: { label: string; children: ReactNode; hint?: ReactNode }) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint ? <span className="field-hint">{hint}</span> : null}
    </label>
  );
}

export function CategorySelect({
  categories,
  type,
  value,
  onChange,
}: {
  categories: Category[];
  type: TxType;
  value: string;
  onChange: (id: string) => void;
}) {
  const options = categories.filter((c) => c.type === type && (!c.archived || c.id === value));
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} aria-label="分类">
      {options.map((c) => (
        <option key={c.id} value={c.id}>
          {c.icon} {c.name}
        </option>
      ))}
    </select>
  );
}

export function AccountSelect({
  accounts,
  value,
  onChange,
}: {
  accounts: Account[];
  value: string;
  onChange: (id: string) => void;
}) {
  const options = accounts.filter((a) => !a.archived || a.id === value);
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} aria-label="账户">
      {options.map((a) => (
        <option key={a.id} value={a.id}>
          {a.name}
        </option>
      ))}
    </select>
  );
}

export function MonthSwitcher({ month, onChange }: { month: MonthKey; onChange: (m: MonthKey) => void }) {
  return (
    <div className="month-switcher">
      <button type="button" className="icon-btn" aria-label="上个月" onClick={() => onChange(addMonthsToKey(month, -1))}>
        ‹
      </button>
      <span className="month-label">{formatMonthKey(month)}</span>
      <button type="button" className="icon-btn" aria-label="下个月" onClick={() => onChange(addMonthsToKey(month, 1))}>
        ›
      </button>
    </div>
  );
}

export function YearSwitcher({ year, onChange }: { year: number; onChange: (y: number) => void }) {
  return (
    <div className="month-switcher">
      <button type="button" className="icon-btn" aria-label="上一年" onClick={() => onChange(year - 1)}>
        ‹
      </button>
      <span className="month-label">{year}年</span>
      <button type="button" className="icon-btn" aria-label="下一年" onClick={() => onChange(year + 1)}>
        ›
      </button>
    </div>
  );
}
