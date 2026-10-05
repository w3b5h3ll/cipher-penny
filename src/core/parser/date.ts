import { addDays, addMonths, dayOfWeek, isValidISODate, parseISODate, toISODate } from '../dates';
import type { ISODate } from '../model';

export interface DateMatch {
  date: ISODate;
  start: number;
  end: number;
}

const RELATIVE_DAYS: Record<string, number> = {
  大前天: -3,
  前天: -2,
  昨天: -1,
  昨日: -1,
  昨晚: -1,
  今天: 0,
  今日: 0,
  今早: 0,
  今晚: 0,
};

const WEEKDAY: Record<string, number> = {
  一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6, 日: 0, 天: 0,
  '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 0,
};

type Resolver = (m: RegExpExecArray, today: ISODate) => ISODate | null;

/** Pattern order matters: more specific forms first. */
const PATTERNS: Array<[RegExp, Resolver]> = [
  [
    /(\d{4})[年\-/.](\d{1,2})[月\-/.](\d{1,2})[日号]?/,
    (m) => validOrNull(toISODate(Number(m[1]), Number(m[2]), Number(m[3]))),
  ],
  [
    /(\d{1,2})月(\d{1,2})(?:日|号)?(?!\d)/,
    (m, today) => {
      const { year } = parseISODate(today);
      const date = validOrNull(toISODate(year, Number(m[1]), Number(m[2])));
      if (!date) return null;
      return date > today ? validOrNull(toISODate(year - 1, Number(m[1]), Number(m[2]))) : date;
    },
  ],
  [/(大前天|前天|昨天|昨日|昨晚|今天|今日|今早|今晚)/, (m, today) => addDays(today, RELATIVE_DAYS[m[1]!] ?? 0)],
  [
    /(上上|上)(?:周|星期|礼拜)([一二三四五六日天1-7])/,
    (m, today) => {
      const weeksBack = m[1] === '上上' ? 2 : 1;
      const monday = addDays(today, -((dayOfWeek(today) + 6) % 7) - 7 * weeksBack);
      return addDays(monday, (WEEKDAY[m[2]!]! + 6) % 7);
    },
  ],
  [
    /(?:周|星期|礼拜)([一二三四五六日天1-7])/,
    (m, today) => {
      const back = (dayOfWeek(today) - WEEKDAY[m[1]!]! + 7) % 7;
      return addDays(today, -back);
    },
  ],
  [
    /(?<!\d)(\d{1,2})[号日](?![\d线楼院])/,
    (m, today) => {
      const day = Number(m[1]);
      const { year, month } = parseISODate(today);
      const date = validOrNull(toISODate(year, month, day));
      if (date && date <= today) return date;
      const prev = addMonths(toISODate(year, month, 1), -1);
      const p = parseISODate(prev);
      return validOrNull(toISODate(p.year, p.month, day));
    },
  ],
];

function validOrNull(iso: ISODate): ISODate | null {
  return isValidISODate(iso) ? iso : null;
}

/** Finds the first date expression in normalised text (F-QA-4). */
export function findDate(text: string, today: ISODate): DateMatch | null {
  for (const [re, resolve] of PATTERNS) {
    const m = re.exec(text);
    if (!m) continue;
    const date = resolve(m, today);
    if (date) return { date, start: m.index, end: m.index + m[0].length };
  }
  return null;
}
