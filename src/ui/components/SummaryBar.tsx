import type { Cents } from '../../core/model';
import { formatMoney } from '../../core/money';
import type { Spending } from '../../core/stats';

/** Total, count and a per-day/per-month average; `periods` is 0 for periods that haven't started. */
export function SummaryBar({ spending, periods, averageLabel }: { spending: Spending; periods: number; averageLabel: string }) {
  const average: Cents | null = periods > 0 ? Math.round(spending.total / periods) : null;
  return (
    <div className="summary">
      <div>
        <span className="muted small">支出</span>
        <strong className="expense">{formatMoney(spending.total)}</strong>
      </div>
      <div>
        <span className="muted small">笔数</span>
        <strong>{spending.count}</strong>
      </div>
      <div>
        <span className="muted small">{averageLabel}</span>
        <strong>{average === null ? '—' : formatMoney(average)}</strong>
      </div>
    </div>
  );
}
