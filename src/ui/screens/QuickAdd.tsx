import { useCallback, useState, type FormEvent, type KeyboardEvent } from 'react';
import { todayISO } from '../../core/dates';
import { fallbackCategory } from '../../core/defaults';
import { addTransactions } from '../../core/ledger';
import type { TransactionInput, TxType, VaultData } from '../../core/model';
import { centsToInput, formatMoney, parseAmount } from '../../core/money';
import { parseEntries } from '../../core/parser/parse';
import { session } from '../../state/session';
import { AccountSelect, CategorySelect, TypeToggle } from '../components/controls';
import { useLookups, useVault } from '../hooks';
import { useSpeech } from '../voice';

interface DraftForm {
  key: number;
  type: TxType;
  amountText: string;
  categoryId: string;
  accountId: string;
  date: string;
  note: string;
}

let draftKey = 0;

const NO_AMOUNT_MESSAGE = '没有识别到金额，试试“午饭 35”这样的说法';

function buildDrafts(input: string, data: VaultData, defaultAccountId: string): DraftForm[] {
  return parseEntries(input, { today: todayISO(), categories: data.categories, accounts: data.accounts }).map((d) => ({
    key: ++draftKey,
    type: d.type,
    amountText: centsToInput(d.amount),
    categoryId: d.categoryId,
    accountId: d.accountId ?? defaultAccountId,
    date: d.date,
    note: d.note,
  }));
}

/** F-QA-1, F-QA-7, F-QA-8, F-QA-9 */
export function QuickAdd({ initialText, onSaved }: { initialText?: string; onSaved?: () => void }) {
  const data = useVault();
  const lookups = useLookups(data);
  const defaultAccountId = lookups.activeAccounts[0]?.id ?? '';
  const [text, setText] = useState(initialText ?? '');
  // F-QA-9: `#/add?text=...` shows drafts immediately; the route remounts us when the text changes.
  const [drafts, setDrafts] = useState<DraftForm[]>(() =>
    initialText ? buildDrafts(initialText, data, defaultAccountId) : [],
  );
  const [message, setMessage] = useState<string | null>(() =>
    initialText && drafts.length === 0 ? NO_AMOUNT_MESSAGE : null,
  );

  function parse(input: string) {
    const next = buildDrafts(input, data, defaultAccountId);
    setMessage(next.length === 0 ? NO_AMOUNT_MESSAGE : null);
    setDrafts(next);
  }

  const appendDictation = useCallback((spoken: string) => {
    setText((prev) => (prev.trim() ? `${prev.trim()}，${spoken}` : spoken));
  }, []);
  const speech = useSpeech(appendDictation);

  function submitText(e?: FormEvent) {
    e?.preventDefault();
    if (text.trim()) parse(text);
  }

  function onKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      submitText();
    }
  }

  function patch(key: number, p: Partial<DraftForm>) {
    setDrafts((list) => list.map((d) => (d.key === key ? { ...d, ...p } : d)));
  }

  function changeType(d: DraftForm, type: TxType) {
    const current = lookups.category(d.categoryId);
    const categoryId = current?.type === type ? d.categoryId : (fallbackCategory(data.categories, type)?.id ?? '');
    patch(d.key, { type, categoryId });
  }

  const invalid = drafts.some((d) => !parseAmount(d.amountText) || !d.categoryId || !d.accountId || !d.date);

  function saveAll() {
    if (invalid || drafts.length === 0) return;
    const inputs: TransactionInput[] = drafts.map((d) => ({
      type: d.type,
      amount: parseAmount(d.amountText)!,
      categoryId: d.categoryId,
      accountId: d.accountId,
      date: d.date,
      note: d.note.trim(),
    }));
    session.update((v) => addTransactions(v, inputs));
    const total = inputs.reduce((s, i) => s + (i.type === 'expense' ? i.amount : 0), 0);
    setMessage(`已保存 ${inputs.length} 笔${total ? `，支出 ${formatMoney(total)}` : ''}`);
    setDrafts([]);
    setText('');
    onSaved?.();
  }

  return (
    <section className="card quick-add">
      <form onSubmit={submitText} className="quick-input">
        <textarea
          value={speech.listening && speech.interim ? `${text}${text ? '，' : ''}${speech.interim}` : text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          rows={2}
          placeholder="说或输入：昨天打车28，晚上和朋友吃饭260"
          aria-label="快速记账"
        />
        <div className="quick-actions">
          {speech.supported ? (
            <button
              type="button"
              className={speech.listening ? 'mic listening' : 'mic'}
              onClick={speech.listening ? speech.stop : speech.start}
              aria-label={speech.listening ? '停止语音输入' : '语音输入'}
              title={speech.listening ? '停止' : '语音输入'}
            >
              {speech.listening ? '■' : '🎤'}
            </button>
          ) : null}
          <button type="submit" className="primary" disabled={!text.trim()}>
            识别
          </button>
        </div>
      </form>
      {speech.error ? <p className="error small">{speech.error}</p> : null}
      {!speech.supported ? <p className="muted small">当前浏览器不支持语音识别，可以使用输入法自带的语音输入。</p> : null}

      {drafts.length > 0 ? (
        <div className="drafts">
          {drafts.map((d) => (
            <div key={d.key} className={`draft draft-${d.type}`}>
              <div className="draft-row">
                <TypeToggle value={d.type} onChange={(t) => changeType(d, t)} />
                <input
                  className="amount-input"
                  inputMode="decimal"
                  value={d.amountText}
                  onChange={(e) => patch(d.key, { amountText: e.target.value })}
                  aria-label="金额"
                  aria-invalid={!parseAmount(d.amountText)}
                />
                <button type="button" className="icon-btn" aria-label="删除这条" onClick={() => setDrafts((l) => l.filter((x) => x.key !== d.key))}>
                  ✕
                </button>
              </div>
              <div className="draft-row">
                <CategorySelect categories={data.categories} type={d.type} value={d.categoryId} onChange={(id) => patch(d.key, { categoryId: id })} />
                <AccountSelect accounts={data.accounts} value={d.accountId} onChange={(id) => patch(d.key, { accountId: id })} />
                <input type="date" value={d.date} onChange={(e) => patch(d.key, { date: e.target.value })} aria-label="日期" />
              </div>
              <input value={d.note} onChange={(e) => patch(d.key, { note: e.target.value })} placeholder="备注" aria-label="备注" />
            </div>
          ))}
          <div className="row end">
            <button type="button" onClick={() => setDrafts([])}>
              取消
            </button>
            <button type="button" className="primary" disabled={invalid} onClick={saveAll}>
              保存 {drafts.length} 笔
            </button>
          </div>
        </div>
      ) : null}
      {message ? <p className="muted small" role="status">{message}</p> : null}
    </section>
  );
}
