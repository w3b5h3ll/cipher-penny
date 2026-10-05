import { useMemo, useState } from 'react';
import { formatDayLabel, monthKeyOf, todayISO } from '../../core/dates';
import { formatMoney } from '../../core/money';
import { groupByDate, summarize, transactionsInMonth } from '../../core/stats';
import { MonthSwitcher } from '../components/controls';
import { SummaryBar } from '../components/SummaryBar';
import { useLookups, useVault } from '../hooks';
import { navigate } from '../router';
import { QuickAdd } from './QuickAdd';

/** F-TX-2 */
export function HomeScreen({ initialText }: { initialText?: string }) {
  const data = useVault();
  const lookups = useLookups(data);
  const today = todayISO();
  const [month, setMonth] = useState(monthKeyOf(today));

  const monthTxs = useMemo(() => transactionsInMonth(data.transactions, month), [data.transactions, month]);
  const groups = useMemo(() => groupByDate(monthTxs), [monthTxs]);
  const summary = useMemo(() => summarize(monthTxs), [monthTxs]);

  return (
    <div className="stack">
      <QuickAdd initialText={initialText} onSaved={() => initialText && navigate('/')} />

      <div className="row between">
        <MonthSwitcher month={month} onChange={setMonth} />
        <button type="button" onClick={() => navigate('/tx/new')}>
          + 手动记一笔
        </button>
      </div>

      <SummaryBar summary={summary} />

      {groups.length === 0 ? (
        <p className="empty">这个月还没有账单</p>
      ) : (
        groups.map((g) => (
          <section key={g.date} className="card day">
            <header className="day-header">
              <span>{formatDayLabel(g.date, today)}</span>
              <span className="muted small">
                {g.summary.expense ? `支出 ${formatMoney(g.summary.expense)}` : ''}
                {g.summary.expense && g.summary.income ? ' · ' : ''}
                {g.summary.income ? `收入 ${formatMoney(g.summary.income)}` : ''}
              </span>
            </header>
            <ul className="tx-list">
              {g.items.map((t) => {
                const category = lookups.category(t.categoryId);
                const account = lookups.account(t.accountId);
                return (
                  <li key={t.id}>
                    <button type="button" className="tx-row" onClick={() => navigate(`/tx/${t.id}`)}>
                      <span className="tx-icon" aria-hidden>
                        {category?.icon ?? '❔'}
                      </span>
                      <span className="tx-main">
                        <span className="tx-title">
                          {category?.name ?? '未知分类'}
                          {t.recurringId ? <span className="badge">周期</span> : null}
                        </span>
                        <span className="tx-sub muted small">
                          {[t.note, account?.name].filter(Boolean).join(' · ')}
                        </span>
                      </span>
                      <span className={`tx-amount ${t.type}`}>
                        {t.type === 'expense' ? '-' : '+'}
                        {formatMoney(t.amount).slice(1)}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </section>
        ))
      )}
    </div>
  );
}
