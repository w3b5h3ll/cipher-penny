import { useState, type FormEvent } from 'react';
import { formatDayLabel, todayISO } from '../../core/dates';
import { fallbackCategory } from '../../core/defaults';
import { newId } from '../../core/id';
import { deleteRecurring, setRecurringActive, upsertRecurring } from '../../core/ledger';
import { FREQUENCY_LABEL, type Frequency, type RecurringRule } from '../../core/model';
import { centsToInput, formatMoney, parseAmount } from '../../core/money';
import { applyRecurring, nextOccurrence } from '../../core/recurring';
import { session } from '../../state/session';
import { AccountSelect, CategorySelect, Field } from '../components/controls';
import { useLookups, useVault } from '../hooks';
import { navigate } from '../router';

function describeFrequency(rule: Pick<RecurringRule, 'frequency' | 'interval'>): string {
  return rule.interval === 1 ? `每${FREQUENCY_LABEL[rule.frequency]}` : `每 ${rule.interval} ${FREQUENCY_LABEL[rule.frequency]}`;
}

/** F-REC-4 */
export function RecurringListScreen() {
  const data = useVault();
  const lookups = useLookups(data);
  const today = todayISO();

  return (
    <div className="stack">
      <div className="row between">
        <h2>周期账单</h2>
        <button type="button" className="primary" onClick={() => navigate('/recurring/new')}>
          + 新建
        </button>
      </div>
      <p className="muted small">订阅、房租、话费等固定支出。每次解锁时会自动补记到今天为止应发生的账单。</p>
      {data.recurring.length === 0 ? (
        <p className="empty">还没有周期账单</p>
      ) : (
        <ul className="card plain-list">
          {data.recurring.map((r) => {
            const next = r.active ? nextOccurrence(r, today) : undefined;
            const c = lookups.category(r.categoryId);
            return (
              <li key={r.id} className={r.active ? 'rule' : 'rule paused'}>
                <button type="button" className="tx-row" onClick={() => navigate(`/recurring/${r.id}`)}>
                  <span className="tx-icon" aria-hidden>
                    {c?.icon ?? '🔁'}
                  </span>
                  <span className="tx-main">
                    <span className="tx-title">{r.name}</span>
                    <span className="tx-sub muted small">
                      {describeFrequency(r)}
                      {r.active ? (next ? ` · 下次 ${formatDayLabel(next, today)}` : ' · 已结束') : ' · 已暂停'}
                    </span>
                  </span>
                  <span className="tx-amount">{formatMoney(r.amount)}</span>
                </button>
                <button
                  type="button"
                  className="small-btn"
                  onClick={() => session.update((d) => setRecurringActive(d, r.id, !r.active, today))}
                >
                  {r.active ? '暂停' : '恢复'}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/** F-REC-1, F-REC-4. `id` undefined means a new rule. */
export function RecurringEditScreen({ id }: { id?: string }) {
  const data = useVault();
  const lookups = useLookups(data);
  const today = todayISO();
  const existing = id ? data.recurring.find((r) => r.id === id) : undefined;
  const subscription = data.categories.find((c) => c.name === '订阅' && !c.archived);

  const [name, setName] = useState(existing?.name ?? '');
  const type = existing?.type ?? 'expense';
  const [amountText, setAmountText] = useState(existing ? centsToInput(existing.amount) : '');
  const [categoryId, setCategoryId] = useState(
    existing?.categoryId ?? subscription?.id ?? fallbackCategory(data.categories, 'expense')?.id ?? '',
  );
  const [accountId, setAccountId] = useState(existing?.accountId ?? lookups.activeAccounts[0]?.id ?? '');
  const [note, setNote] = useState(existing?.note ?? '');
  const [frequency, setFrequency] = useState<Frequency>(existing?.frequency ?? 'monthly');
  const [interval, setIntervalValue] = useState(existing?.interval ?? 1);
  const [startDate, setStartDate] = useState(existing?.startDate ?? today);
  const [endDate, setEndDate] = useState(existing?.endDate ?? '');

  if (id && !existing) {
    return (
      <div className="card">
        <p>周期账单不存在。</p>
        <button type="button" onClick={() => navigate('/recurring')}>返回</button>
      </div>
    );
  }

  const amount = parseAmount(amountText);
  const valid =
    name.trim() && amount && categoryId && accountId && startDate && interval >= 1 && (!endDate || endDate >= startDate);
  const backfills = !existing && startDate < today;

  function save(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    const rule: RecurringRule = {
      ...existing,
      id: existing?.id ?? newId(),
      name: name.trim(),
      type,
      amount: amount!,
      categoryId,
      accountId,
      note: note.trim(),
      frequency,
      interval: Math.floor(interval),
      startDate,
      endDate: endDate || undefined,
      active: existing?.active ?? true,
    };
    session.update((d) => applyRecurring(upsertRecurring(d, rule), today).data);
    navigate('/recurring');
  }

  function remove() {
    if (!existing || !window.confirm(`删除周期账单「${existing.name}」？已生成的账单会保留。`)) return;
    session.update((d) => deleteRecurring(d, existing.id));
    navigate('/recurring');
  }

  return (
    <form className="card stack" onSubmit={save}>
      <h2>{existing ? '编辑周期账单' : '新建周期账单'}</h2>
      <Field label="名称">
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="例如：iCloud 200GB" autoFocus={!existing} />
      </Field>
      <div className="grid-2">
        <Field label="金额（元）">
          <input className="amount-input" inputMode="decimal" value={amountText} onChange={(e) => setAmountText(e.target.value)} />
        </Field>
        <Field label="频率">
          <div className="row">
            <span>每</span>
            <input
              type="number"
              min={1}
              max={99}
              className="narrow"
              value={interval}
              onChange={(e) => setIntervalValue(Number(e.target.value) || 1)}
              aria-label="间隔"
            />
            <select value={frequency} onChange={(e) => setFrequency(e.target.value as Frequency)} aria-label="周期单位">
              {(Object.keys(FREQUENCY_LABEL) as Frequency[]).map((f) => (
                <option key={f} value={f}>
                  {FREQUENCY_LABEL[f]}
                </option>
              ))}
            </select>
          </div>
        </Field>
        <Field label="分类">
          <CategorySelect categories={data.categories} type={type} value={categoryId} onChange={setCategoryId} />
        </Field>
        <Field label="账户">
          <AccountSelect accounts={data.accounts} value={accountId} onChange={setAccountId} />
        </Field>
        <Field label="开始日期" hint="按月的规则以这一天为准，短月份取月底">
          <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
        </Field>
        <Field label="结束日期（可选）">
          <input type="date" value={endDate} min={startDate} onChange={(e) => setEndDate(e.target.value)} />
        </Field>
      </div>
      <Field label="账单备注（留空则使用名称）">
        <input value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      {backfills ? <p className="notice small">开始日期早于今天：保存后会补记从开始日期到今天的账单。</p> : null}
      <div className="row between">
        <div className="row">
          <button type="submit" className="primary" disabled={!valid}>
            保存
          </button>
          <button type="button" onClick={() => navigate('/recurring')}>
            取消
          </button>
        </div>
        {existing ? (
          <button type="button" className="danger" onClick={remove}>
            删除
          </button>
        ) : null}
      </div>
    </form>
  );
}
