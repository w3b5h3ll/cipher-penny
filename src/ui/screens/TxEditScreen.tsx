import { useState, type FormEvent } from 'react';
import { todayISO } from '../../core/dates';
import { fallbackCategory } from '../../core/defaults';
import { addTransactions, deleteTransaction, updateTransaction } from '../../core/ledger';
import type { TransactionInput } from '../../core/model';
import { centsToInput, parseAmount } from '../../core/money';
import { session } from '../../state/session';
import { AccountSelect, CategorySelect, Field } from '../components/controls';
import { useLookups, useVault } from '../hooks';
import { navigate } from '../router';

function goBack() {
  if (window.history.length > 1) window.history.back();
  else navigate('/');
}

/** F-TX-1, F-TX-3. `id` undefined means a new transaction. */
export function TxEditScreen({ id }: { id?: string }) {
  const data = useVault();
  const lookups = useLookups(data);
  const existing = id ? data.transactions.find((t) => t.id === id) : undefined;

  const type = existing?.type ?? 'expense';
  const [amountText, setAmountText] = useState(existing ? centsToInput(existing.amount) : '');
  const [categoryId, setCategoryId] = useState(
    existing?.categoryId ?? fallbackCategory(data.categories, 'expense')?.id ?? '',
  );
  const [accountId, setAccountId] = useState(existing?.accountId ?? lookups.activeAccounts[0]?.id ?? '');
  const [date, setDate] = useState(existing?.date ?? todayISO());
  const [note, setNote] = useState(existing?.note ?? '');

  if (id && !existing) {
    return (
      <div className="card">
        <p>账单不存在或已删除。</p>
        <button type="button" onClick={() => navigate('/')}>返回</button>
      </div>
    );
  }

  const amount = parseAmount(amountText);
  const valid = amount !== null && amount > 0 && categoryId && accountId && date;
  const rule = existing?.recurringId ? data.recurring.find((r) => r.id === existing.recurringId) : undefined;

  function save(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    const input: TransactionInput = { type, amount: amount!, categoryId, accountId, date, note: note.trim() };
    if (existing) {
      session.update((v) => updateTransaction(v, existing.id, input));
    } else {
      session.update((v) => addTransactions(v, [input]));
    }
    goBack();
  }

  function remove() {
    if (!existing || !window.confirm('确定删除这笔账单？')) return;
    session.update((v) => deleteTransaction(v, existing.id));
    goBack();
  }

  return (
    <form className="card stack" onSubmit={save}>
      <h2>{existing ? '编辑账单' : '记一笔'}</h2>
      <Field label="金额（元）">
        <input
          className="amount-input large"
          inputMode="decimal"
          autoFocus={!existing}
          value={amountText}
          onChange={(e) => setAmountText(e.target.value)}
          placeholder="0.00"
        />
      </Field>
      <div className="grid-2">
        <Field label="分类">
          <CategorySelect categories={data.categories} type={type} value={categoryId} onChange={setCategoryId} />
        </Field>
        <Field label="账户">
          <AccountSelect accounts={data.accounts} value={accountId} onChange={setAccountId} />
        </Field>
      </div>
      <Field label="日期">
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
      </Field>
      <Field label="备注">
        <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="可选" />
      </Field>
      {rule ? <p className="muted small">由周期账单「{rule.name}」自动生成。修改这一笔不会影响规则。</p> : null}
      <div className="row between">
        <div className="row">
          <button type="submit" className="primary" disabled={!valid}>
            保存
          </button>
          <button type="button" onClick={goBack}>
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
