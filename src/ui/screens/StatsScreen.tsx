import { useMemo, useState } from 'react';
import { monthKeyOf, todayISO, type MonthKey } from '../../core/dates';
import type { Transaction } from '../../core/model';
import { formatCents, formatMoney } from '../../core/money';
import {
  daysElapsed,
  monthlySpending,
  monthsElapsed,
  spending,
  spendingByAccount,
  spendingByCategory,
  transactionsInMonth,
  transactionsInYear,
  type GroupTotal,
} from '../../core/stats';
import { MonthSwitcher, YearSwitcher } from '../components/controls';
import { SummaryBar } from '../components/SummaryBar';
import { useLookups, useVault } from '../hooks';

type Period = 'month' | 'year';

const PERIOD_LABEL: Record<Period, string> = { month: '按月', year: '按年' };

/** F-STAT-1 ~ F-STAT-4 */
export function StatsScreen() {
  const data = useVault();
  const lookups = useLookups(data);
  const today = todayISO();
  const [period, setPeriod] = useState<Period>('month');
  const [month, setMonth] = useState(monthKeyOf(today));
  const [year, setYear] = useState(Number(today.slice(0, 4)));

  const txs = useMemo(
    () => (period === 'month' ? transactionsInMonth(data.transactions, month) : transactionsInYear(data.transactions, year)),
    [data.transactions, period, month, year],
  );
  const total = useMemo(() => spending(txs), [txs]);
  const byCategory = useMemo(() => spendingByCategory(txs), [txs]);
  const byAccount = useMemo(() => spendingByAccount(txs), [txs]);

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
      {period === 'month' ? (
        <SummaryBar spending={total} periods={daysElapsed(month, today)} averageLabel="日均" />
      ) : (
        <SummaryBar spending={total} periods={monthsElapsed(year, today)} averageLabel="月均" />
      )}
      {period === 'year' ? (
        <YearTrend transactions={data.transactions} year={year} today={today} yearTotal={total.total} onOpenMonth={openMonth} />
      ) : null}
      <TotalsCard
        title="分类"
        totals={byCategory}
        label={(id) => {
          const c = lookups.category(id);
          return c ? `${c.icon} ${c.name}` : '未知分类';
        }}
      />
      <TotalsCard title="账户" totals={byAccount} label={(id) => lookups.account(id)?.name ?? '未知账户'} />
    </div>
  );
}

function YearTrend({
  transactions,
  year,
  today,
  yearTotal,
  onOpenMonth,
}: {
  transactions: Transaction[];
  year: number;
  today: string;
  yearTotal: number;
  onOpenMonth: (month: MonthKey) => void;
}) {
  const months = useMemo(() => monthlySpending(transactions, year), [transactions, year]);
  const currentMonth = monthKeyOf(today);
  const active = months.filter((m) => m.count > 0);
  const max = Math.max(0, ...months.map((m) => m.total));
  const barHeight = (cents: number) => (cents && max ? `max(2px, ${(cents / max) * 100}%)` : '0');

  return (
    <section className="card stack">
      <h2>月度趋势</h2>
      {active.length === 0 ? (
        <p className="empty">{year}年没有支出记录</p>
      ) : (
        <>
          <div className="trend">
            {months.map((m, i) => {
              const label = `${i + 1}月：支出 ${formatMoney(m.total)}，${m.count} 笔`;
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
                    <span className="trend-bar" style={{ height: barHeight(m.total) }} />
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
                <th>笔数</th>
                <th>占全年</th>
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
                  <td>{formatCents(m.total)}</td>
                  <td>{m.count}</td>
                  <td>{yearTotal ? ((m.total / yearTotal) * 100).toFixed(1) : '0.0'}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </section>
  );
}

function TotalsCard({ title, totals, label }: { title: string; totals: GroupTotal[]; label: (id: string) => string }) {
  const maxTotal = totals[0]?.total ?? 0;
  return (
    <section className="card stack">
      <h2>{title}</h2>
      {totals.length === 0 ? (
        <p className="empty">没有支出记录</p>
      ) : (
        <ul className="bars">
          {totals.map((t) => (
            <li key={t.id}>
              <div className="bar-label">
                <span>
                  {label(t.id)} <span className="muted small">{t.count} 笔</span>
                </span>
                <span>
                  {formatMoney(t.total)} <span className="muted small">{(t.ratio * 100).toFixed(1)}%</span>
                </span>
              </div>
              <div className="bar-track">
                <div className="bar-fill" style={{ width: `${maxTotal ? (t.total / maxTotal) * 100 : 0}%` }} />
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
