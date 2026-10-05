import { formatMoney } from '../../core/money';
import type { Summary } from '../../core/stats';

export function SummaryBar({ summary }: { summary: Summary }) {
  return (
    <div className="summary">
      <div>
        <span className="muted small">支出</span>
        <strong className="expense">{formatMoney(summary.expense)}</strong>
      </div>
      <div>
        <span className="muted small">收入</span>
        <strong className="income">{formatMoney(summary.income)}</strong>
      </div>
      <div>
        <span className="muted small">结余</span>
        <strong>{formatMoney(summary.net)}</strong>
      </div>
    </div>
  );
}
