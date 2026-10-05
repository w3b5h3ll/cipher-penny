import { useMemo, useState } from 'react';
import { monthKeyOf, todayISO } from '../../core/dates';
import { ACCOUNT_KIND_LABEL, type TxType } from '../../core/model';
import { formatMoney } from '../../core/money';
import { accountBalances, summarize, totalsByCategory, transactionsInMonth } from '../../core/stats';
import { MonthSwitcher, TypeToggle } from '../components/controls';
import { SummaryBar } from '../components/SummaryBar';
import { useLookups, useVault } from '../hooks';

/** F-STAT-1 ~ F-STAT-3 */
export function StatsScreen() {
  const data = useVault();
  const lookups = useLookups(data);
  const [month, setMonth] = useState(monthKeyOf(todayISO()));
  const [type, setType] = useState<TxType>('expense');

  const monthTxs = useMemo(() => transactionsInMonth(data.transactions, month), [data.transactions, month]);
  const summary = useMemo(() => summarize(monthTxs), [monthTxs]);
  const totals = useMemo(() => totalsByCategory(monthTxs, type), [monthTxs, type]);
  const balances = useMemo(() => accountBalances(data), [data]);
  const maxTotal = totals[0]?.total ?? 0;

  return (
    <div className="stack">
      <MonthSwitcher month={month} onChange={setMonth} />
      <SummaryBar summary={summary} />

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
    </div>
  );
}
