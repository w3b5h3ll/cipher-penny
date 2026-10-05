import type { Cents } from '../model';
import { CN_NUMERAL_CHARS, parseChineseInteger } from './chineseNumber';

const CN = `[${CN_NUMERAL_CHARS}]+`;
const CURRENCY_UNIT = '块钱|块|元|圆|毛|角|rmb|RMB';
const SPEND_VERB = '花了|花费了?|花掉了?|消费了?|付了|支付了?|用了|收到了?|收入了?|赚了|进账|到账|一共|总共|共计|共';

/** Full-width -> half-width, ¥ prefix -> 元 suffix, so later regexes only see one form. */
export function normalizeText(input: string): string {
  return input
    .replace(/[\uFF01-\uFF5E]/g, (ch) => String.fromCharCode(ch.charCodeAt(0) - 0xfee0))
    .replace(/\u3000/g, ' ')
    .replace(/[¥￥]\s*(\d+(?:\.\d+)?)/g, '$1元');
}

/**
 * Rewrites Chinese numerals that are clearly amounts into digits:
 * those followed by a currency unit ("三十五块") or preceded by a spend verb ("花了三十五").
 * Bare numerals elsewhere ("一起", "十一假期") are left untouched.
 */
export function convertChineseAmounts(text: string): string {
  const toDigits = (cn: string) => {
    const n = parseChineseInteger(cn);
    return n === null ? cn : String(n);
  };
  const spendVerbAtEnd = new RegExp(`(?:${SPEND_VERB})\\s*$`);
  return text
    .replace(
      new RegExp(`(${CN})(\\s*)(${CURRENCY_UNIT})`, 'g'),
      (match: string, cn: string, space: string, unit: string, offset: number, full: string) => {
        // "一块" also means "together" ("一块吃饭"); only treat it as money when context says so.
        if (cn === '一' && unit === '块') {
          const next = full[offset + match.length];
          const moneyNext = next !== undefined && /[钱\d零〇一二两三四五六七八九十毛角]/.test(next);
          if (!moneyNext && !spendVerbAtEnd.test(full.slice(0, offset))) return match;
        }
        return toDigits(cn) + space + unit;
      },
    )
    .replace(new RegExp(`(${SPEND_VERB})(${CN})`, 'g'), (_, verb: string, cn: string) => verb + toDigits(cn))
    .replace(/(\d)(块|元)([一二两三四五六七八九])(?![零〇一二两三四五六七八九十百千万])/g, (_, d: string, unit: string, cn: string) =>
      d + unit + String(parseChineseInteger(cn)),
    );
}

export interface AmountMatch {
  cents: Cents;
  start: number;
  end: number;
  hasUnit: boolean;
}

// Numbers followed by these are counts, times or dates, not money ("2杯", "8点", "5号").
const NOT_MONEY_SUFFIX =
  /^\s*(?:个|杯|次|斤|件|瓶|盒|份|张|本|人|位|点|号|日|月|天|周|年|岁|楼|层|路|公里|km|小时|分钟|折|%|G|g|kg|ml)/;

const AMOUNT_RE = /(\d+(?:\.\d+)?)(\s*(?:块钱|块|元|圆|毛|角|rmb)(?:\s*(\d)(?:\s*(?:毛|角))?)?)?/gi;

/** Finds money-like numbers in already-normalised text. */
export function findAmounts(text: string): AmountMatch[] {
  const result: AmountMatch[] = [];
  for (const m of text.matchAll(AMOUNT_RE)) {
    const start = m.index;
    const prev = text[start - 1];
    if (prev !== undefined && /[\d.]/.test(prev)) continue;
    const [whole, num, unitPart, jiao] = m;
    if (!num) continue;
    const end = start + whole.length;
    if (!unitPart && NOT_MONEY_SUFFIX.test(text.slice(end))) continue;

    let cents: number;
    if (unitPart && /毛|角/.test(unitPart.trim().slice(0, 1))) {
      cents = Math.round(Number(num) * 10);
    } else {
      cents = Math.round(Number(num) * 100) + (jiao ? Number(jiao) * 10 : 0);
    }
    if (!Number.isSafeInteger(cents) || cents <= 0) continue;
    result.push({ cents, start, end, hasUnit: Boolean(unitPart) });
  }
  return result;
}

/** Picks the amount: the first one with a currency unit, otherwise the last number (F-QA-3). */
export function pickAmount(matches: AmountMatch[]): AmountMatch | undefined {
  return matches.find((m) => m.hasUnit) ?? matches[matches.length - 1];
}
