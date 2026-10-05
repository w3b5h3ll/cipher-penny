import type { ISODate } from './model';

// All arithmetic goes through UTC timestamps so DST and the host time zone never shift a date.

const pad = (n: number) => n.toString().padStart(2, '0');

export function toISODate(year: number, month: number, day: number): ISODate {
  return `${year.toString().padStart(4, '0')}-${pad(month)}-${pad(day)}`;
}

export function todayISO(now: Date = new Date()): ISODate {
  return toISODate(now.getFullYear(), now.getMonth() + 1, now.getDate());
}

export function parseISODate(iso: ISODate): { year: number; month: number; day: number } {
  const [y, m, d] = iso.split('-').map(Number);
  return { year: y ?? NaN, month: m ?? NaN, day: d ?? NaN };
}

export function isValidISODate(iso: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false;
  const { year, month, day } = parseISODate(iso);
  return month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month);
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function fromUTC(date: Date): ISODate {
  return toISODate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
}

export function addDays(iso: ISODate, days: number): ISODate {
  const { year, month, day } = parseISODate(iso);
  return fromUTC(new Date(Date.UTC(year, month - 1, day + days)));
}

/**
 * Adds months, clamping to the last day of the target month.
 * `anchorDay` keeps the intended day across short months (Jan 31 -> Feb 28 -> Mar 31).
 */
export function addMonths(iso: ISODate, months: number, anchorDay?: number): ISODate {
  const { year, month, day } = parseISODate(iso);
  const total = year * 12 + (month - 1) + months;
  const y = Math.floor(total / 12);
  const m = (total % 12) + 1;
  return toISODate(y, m, Math.min(anchorDay ?? day, daysInMonth(y, m)));
}

/** 0 = Sunday ... 6 = Saturday */
export function dayOfWeek(iso: ISODate): number {
  const { year, month, day } = parseISODate(iso);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

/** `YYYY-MM` */
export type MonthKey = string;

export function monthKeyOf(iso: ISODate): MonthKey {
  return iso.slice(0, 7);
}

export function addMonthsToKey(key: MonthKey, months: number): MonthKey {
  return addMonths(`${key}-01`, months).slice(0, 7);
}

export function formatMonthKey(key: MonthKey): string {
  const [y, m] = key.split('-');
  return `${y}年${Number(m)}月`;
}

const WEEKDAY_LABEL = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/** "10月5日 周一", with "今天"/"昨天" when applicable. */
export function formatDayLabel(iso: ISODate, today: ISODate): string {
  const { month, day } = parseISODate(iso);
  const base = `${month}月${day}日 ${WEEKDAY_LABEL[dayOfWeek(iso)]}`;
  if (iso === today) return `今天 · ${base}`;
  if (iso === addDays(today, -1)) return `昨天 · ${base}`;
  return base;
}
