import { useCallback, useState, type FormEvent, type KeyboardEvent } from 'react';
import { todayISO } from '../../core/dates';
import { addTransactions } from '../../core/ledger';
import type { TransactionInput, VaultData } from '../../core/model';
import { centsToInput, formatMoney, parseAmount } from '../../core/money';
import { parseEntries } from '../../core/parser/parse';
import { session } from '../../state/session';
import { AccountSelect, CategorySelect } from '../components/controls';
import { useLookups, useVault } from '../hooks';
import { useSpeech } from '../voice';

interface DraftForm {
  key: number;
  amountText: string;
  categoryId: string;
  accountId: string;
  date: string;
  note: string;
}

interface ParseResult {
  drafts: DraftForm[];
  /** Entries the parser classified as income; the app only records spending (F-QA-7). */
  skipped: string[];
}

let draftKey = 0;

function buildDrafts(input: string, data: VaultData, defaultAccountId: string): ParseResult {
  const result: ParseResult = { drafts: [], skipped: [] };
  for (const d of parseEntries(input, { today: todayISO(), categories: data.categories, accounts: data.accounts })) {
    if (d.type === 'income') {
      result.skipped.push(`${d.note || '收入'} ${formatMoney(d.amount)}`);
      continue;
    }
    result.drafts.push({
      key: ++draftKey,
      amountText: centsToInput(d.amount),
      categoryId: d.categoryId,
      accountId: d.accountId ?? defaultAccountId,
      date: d.date,
      note: d.note,
    });
  }
  return result;
}

function parseMessage({ drafts, skipped }: ParseResult): string | null {
  if (skipped.length > 0) return `已跳过收入：${skipped.join('、')}。目前只记录支出。`;
  if (drafts.length === 0) return '没有识别到金额，试试“午饭 35”这样的说法';
  return null;
}

/** F-QA-1, F-QA-7, F-QA-8, F-QA-9 */
export function QuickAdd({ initialText, onSaved }: { initialText?: string; onSaved?: () => void }) {
  const data = useVault();
  const lookups = useLookups(data);
  const defaultAccountId = lookups.activeAccounts[0]?.id ?? '';
  const [text, setText] = useState(initialText ?? '');
  // F-QA-9: `#/add?text=...` shows drafts immediately; the route remounts us when the text changes.
  const [initial] = useState(() => (initialText ? buildDrafts(initialText, data, defaultAccountId) : undefined));
  const [drafts, setDrafts] = useState<DraftForm[]>(initial?.drafts ?? []);
  const [message, setMessage] = useState<string | null>(initial ? parseMessage(initial) : null);

  function parse(input: string) {
    const result = buildDrafts(input, data, defaultAccountId);
    setMessage(parseMessage(result));
    setDrafts(result.drafts);
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

  const invalid = drafts.some((d) => !parseAmount(d.amountText) || !d.categoryId || !d.accountId || !d.date);

  function saveAll() {
    if (invalid || drafts.length === 0) return;
    const inputs: TransactionInput[] = drafts.map((d) => ({
      type: 'expense',
      amount: parseAmount(d.amountText)!,
      categoryId: d.categoryId,
      accountId: d.accountId,
      date: d.date,
      note: d.note.trim(),
    }));
    session.update((v) => addTransactions(v, inputs));
    const total = inputs.reduce((s, i) => s + i.amount, 0);
    setMessage(`已保存 ${inputs.length} 笔，共 ${formatMoney(total)}`);
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
            <div key={d.key} className="draft">
              <div className="draft-row">
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
                <CategorySelect categories={data.categories} type="expense" value={d.categoryId} onChange={(id) => patch(d.key, { categoryId: id })} />
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
