import { fallbackCategory } from '../defaults';
import type { Account, Category, Cents, ISODate, TxType } from '../model';
import { convertChineseAmounts, findAmounts, normalizeText, pickAmount } from './amount';
import { findDate } from './date';

export interface Draft {
  type: TxType;
  amount: Cents;
  categoryId: string;
  accountId?: string;
  date: ISODate;
  note: string;
  /** The text segment this draft came from, for display. */
  source: string;
}

export interface ParseContext {
  today: ISODate;
  categories: Category[];
  accounts?: Account[];
}

const SEGMENT_SEPARATOR = /[,;。!?\n]+|然后|还有|另外|以及/;
const INCOME_HINT = /收到|收入|到账|入账|进账|赚/;
const LEADING_FILLER = /^(?:\s|用|通过|在)+/;
const TRAILING_FILLER =
  /(?:花了|花费了?|花掉了?|消费了?|付了|付款|支付了?|用了|一共|总共|共计|共|大概|大约|是|收到了?|赚了|入账|到账|进账|\s)+$/;
const AFTER_AMOUNT_FILLER = /^(?:左右|多|整|\s)+/;

/** Splits on punctuation/conjunctions, and on whitespace after an amount when another amount follows. */
export function splitSegments(text: string): string[] {
  const coarse = text.split(SEGMENT_SEPARATOR).map((s) => s.trim()).filter(Boolean);
  const result: string[] = [];
  for (const seg of coarse) {
    let rest = seg;
    for (;;) {
      const m = /\d(?:\.\d+)?\s*(?:块钱|块|元|圆)?\s+(?=\D)/.exec(rest);
      if (!m) break;
      const cut = m.index + m[0].length;
      const tail = rest.slice(cut);
      if (!/\d/.test(tail)) break;
      result.push(rest.slice(0, cut).trim());
      rest = tail;
    }
    if (rest.trim()) result.push(rest.trim());
  }
  return result;
}

function longestKeywordMatch(text: string, categories: Category[]): Category | undefined {
  const lower = text.toLowerCase();
  let best: Category | undefined;
  let bestLen = 0;
  for (const c of categories) {
    for (const kw of [c.name, ...c.keywords]) {
      const k = kw.trim().toLowerCase();
      if (!k || !lower.includes(k)) continue;
      // Ties keep the earlier category; defaults list expense categories first.
      if (k.length > bestLen) {
        best = c;
        bestLen = k.length;
      }
    }
  }
  return best;
}

/** F-QA-5: income hint words bias towards income categories; otherwise longest keyword wins. */
export function matchCategory(text: string, categories: Category[]): Category | undefined {
  const active = categories.filter((c) => !c.archived);
  const incomeHint = INCOME_HINT.test(text);
  if (incomeHint) {
    const income = longestKeywordMatch(text, active.filter((c) => c.type === 'income'));
    if (income) return income;
  }
  return (
    longestKeywordMatch(text, active) ??
    fallbackCategory(active, incomeHint ? 'income' : 'expense')
  );
}

function matchAccount(text: string, accounts: Account[]): Account | undefined {
  return accounts
    .filter((a) => !a.archived && a.name && text.includes(a.name))
    .sort((a, b) => b.name.length - a.name.length)[0];
}

function cleanNote(text: string): string {
  return text
    .replace(/\s+/g, ' ')
    .replace(/^[\s,.:;，。：；、-]+|[\s,.:;，。：；、-]+$/g, '')
    .trim();
}

/**
 * Parses free text (typed or dictated) into transaction drafts (F-QA-2 ~ F-QA-6).
 * Pure function: same input and context always give the same drafts.
 */
export function parseEntries(input: string, ctx: ParseContext): Draft[] {
  const text = convertChineseAmounts(normalizeText(input));
  const drafts: Draft[] = [];
  let contextDate = ctx.today;

  for (const segment of splitSegments(text)) {
    let rest = segment;

    const dateMatch = findDate(rest, ctx.today);
    if (dateMatch) {
      contextDate = dateMatch.date;
      rest = `${rest.slice(0, dateMatch.start)} ${rest.slice(dateMatch.end)}`;
    }

    const amount = pickAmount(findAmounts(rest));
    if (!amount) continue;

    const before = rest.slice(0, amount.start);
    const after = rest.slice(amount.end);
    // Classify on the unstripped text so hint words like "收到" still count.
    const withoutAmount = `${before} ${after}`;
    const category = matchCategory(withoutAmount, ctx.categories);
    if (!category) continue;
    const account = ctx.accounts ? matchAccount(withoutAmount, ctx.accounts) : undefined;

    let note = `${before.replace(TRAILING_FILLER, '')} ${after.replace(AFTER_AMOUNT_FILLER, '')}`;
    if (account) note = note.replace(account.name, ' ');
    note = cleanNote(note.replace(LEADING_FILLER, '').replace(TRAILING_FILLER, ''));

    drafts.push({
      type: category.type,
      amount: amount.cents,
      categoryId: category.id,
      ...(account ? { accountId: account.id } : {}),
      date: contextDate,
      note,
      source: segment.trim(),
    });
  }
  return drafts;
}
