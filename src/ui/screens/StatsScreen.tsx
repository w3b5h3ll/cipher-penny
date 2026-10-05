import { useMemo, useState } from 'react';
import { monthKeyOf, todayISO, type MonthKey } from '../../core/dates';
import { ACCOUNT_KIND_LABEL, type Transaction, type TxType, type VaultData } from '../../core/model';
import { formatCents, formatMoney } from '../../core/money';
import {
  accountBalances,
  monthlySummaries,
  monthsElapsed,
  summarize,
  totalsByCategory,
  transactionsInMonth,
  transactionsInYear,
  type Summary,
} from '../../core/stats';
import { MonthSwitcher, TypeToggle, YearSwitcher } from '../components/controls';
import { SummaryBar } from '../components/SummaryBar';
import { useLookups, useVault } from '../hooks';

type Period = 'month' | 'year';

const PERIOD_LABEL: Record<Period, string> = { month: '按月', year: '按年' };

/** F-STAT-1 ~ F-STAT-4 */
export function StatsScreen() {
  const data = useVault();
  const today = todayISO();
  const [period, setPeriod] = useState<Period>('month');
  const [month, setMonth] = useState(monthKeyOf(today));
  const [year, setYear] = useState(Number(today.slice(0, 4)));

  const txs = useMemo(
    () => (period === 'month' ? transactionsInMonth(data.transactions, month) : transactionsInYear(data.transactions, year)),
    [data.transactions, period, month, year],
  );
  const summary = useMemo(() => summarize(txs), [txs]);

  function changePeriod(next: Period) {
    if (next === 'year') setYear(Number(month.slice(0, 4)));
    else if (!month.startsWith(`${year}-`)) setMonth(year === Number(today.slice(0, 4)) ? monthKeyOf(today) : `${year}-01`);
    setPeriod(next);
  }

  function openMonth(key: MonthKey) {
    setMonth(key);
    setPeriod('month');
  }

  return (
    <div className="stack">
      <div className="row between wrap">
        {period === 'month' ? <MonthSwitcher month={month} onChange={setMonth} /> : <YearSwitcher year={year} onChange={setYear} />}
        <div className="segmented" role="radiogroup" aria-label="统计周期">
          {(['month', 'year'] as const).map((p) => (
            <button
              key={p}
              type="button"
              role="radio"
              aria-checked={period === p}
              className={period === p ? 'active' : ''}
              onClick={() => changePeriod(p)}
            >
              {PERIOD_LABEL[p]}
            </button>
          ))}
        </div>
      </div>
      <SummaryBar summary={summary} />
      {period === 'year' ? (
        <YearTrend transactions={data.transactions} year={year} today={today} summary={summary} onOpenMonth={openMonth} />
      ) : null}
      <CategoryTotals txs={txs} data={data} />
      <AccountBalances data={data} />
    </div>
  );
}

function YearTrend({
  transactions,
  year,
  today,
  summary,
  onOpenMonth,
}: {
  transactions: Transaction[];
  year: number;
  today: string;
  summary: Summary;
  onOpenMonth: (month: MonthKey) => void;
}) {
  const months = useMemo(() => monthlySummaries(transactions, year), [transactions, year]);
  const elapsed = monthsElapsed(year, today);
  const currentMonth = monthKeyOf(today);
  const active = months.filter((m) => m.income !== 0 || m.expense !== 0);
  const max = Math.max(0, ...months.flatMap((m) => [m.income, m.expense]));
  const barHeight = (cents: number) => (cents && max ? `max(2px, ${(cents / max) * 100}%)` : '0');

  return (
    <section className="card stack">
      <div className="row between wrap">
        <h2>月度趋势</h2>
        <span className="legend small muted">
          <i className="dot expense" />
          支出
          <i className="dot income" />
          收入
        </span>
      </div>
      {active.length === 0 ? (
        <p className="empty">{year}年没有记录</p>
      ) : (
        <>
          {elapsed > 0 ? (
            <p className="muted small">
              月均支出 {formatMoney(Math.round(summary.expense / elapsed))} · 月均收入{' '}
              {formatMoney(Math.round(summary.income / elapsed))}（按 {elapsed} 个月计算）
            </p>
          ) : null}
          <div className="trend">
            {months.map((m, i) => {
              const label = `${i + 1}月：支出 ${formatMoney(m.expense)}，收入 ${formatMoney(m.income)}`;
              return (
                <button
                  key={m.month}
                  type="button"
                  className={`trend-col${m.month === currentMonth ? ' current' : ''}`}
                  aria-label={label}
                  title={label}
                  onClick={() => onOpenMonth(m.month)}
                >
                  <span className="trend-bars">
                    <span className="trend-bar expense" style={{ height: barHeight(m.expense) }} />
                    <span className="trend-bar income" style={{ height: barHeight(m.income) }} />
                  </span>
                  <span className="trend-label">{i + 1}</span>
                </button>
              );
            })}
          </div>
          <table className="month-table">
            <thead>
              <tr>
                <th>月份</th>
                <th>支出</th>
                <th>收入</th>
                <th>结余</th>
              </tr>
            </thead>
            <tbody>
              {active.map((m) => (
                <tr key={m.month}>
                  <td>
                    <button type="button" className="link" onClick={() => onOpenMonth(m.month)}>
                      {Number(m.month.slice(5))}月
                    </button>
                  </td>
                  <td>{formatCents(m.expense)}</td>
                  <td>{formatCents(m.income)}</td>
                  <td className={m.net < 0 ? 'expense' : ''}>{formatCents(m.net)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </section>
  );
}

function CategoryTotals({ txs, data }: { txs: Transaction[]; data: VaultData }) {
  const lookups = useLookups(data);
  const [type, setType] = useState<TxType>('expense');
  const totals = useMemo(() => totalsByCategory(txs, type), [txs, type]);
  const maxTotal = totals[0]?.total ?? 0;

  return (
    <section className="card stack">
      <div className="row between">
        <h2>分类</h2>
        <TypeToggle value={type} onChange={setType} />
      </div>
      {totals.length === 0 ? (
        <p className="empty">没有{type === 'expense' ? '支出' : '收入'}记录</p>
      ) : (
        <ul className="bars">
          {totals.map((t) => {
            const c = lookups.category(t.categoryId);
            return (
              <li key={t.categoryId}>
                <div className="bar-label">
                  <span>
                    {c?.icon} {c?.name ?? '未知分类'} <span className="muted small">{t.count} 笔</span>
                  </span>
                  <span>
                    {formatMoney(t.total)} <span className="muted small">{(t.ratio * 100).toFixed(1)}%</span>
                  </span>
                </div>
                <div className="bar-track">
                  <div
                    className={`bar-fill ${type}`}
                    style={{ width: `${maxTotal ? (t.total / maxTotal) * 100 : 0}%` }}
                  />
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function AccountBalances({ data }: { data: VaultData }) {
  const balances = useMemo(() => accountBalances(data), [data]);
  return (
    <section className="card stack">
      <h2>账户余额</h2>
      <ul className="plain-list">
        {data.accounts
          .filter((a) => !a.archived)
          .map((a) => {
            const balance = balances.get(a.id) ?? 0;
            return (
              <li key={a.id} className="row between">
                <span>
                  {a.name} <span className="muted small">{ACCOUNT_KIND_LABEL[a.kind]}</span>
                </span>
                <strong className={balance < 0 ? 'expense' : ''}>{formatMoney(balance)}</strong>
              </li>
            );
          })}
      </ul>
      <p className="muted small">余额 = 初始余额 + 收入 − 支出，可在设置中修改初始余额。</p>
    </section>
  );
}
