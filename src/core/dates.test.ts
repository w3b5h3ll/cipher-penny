import { describe, expect, it } from 'vitest';
import {
  addDays,
  addMonths,
  addMonthsToKey,
  dayOfWeek,
  daysInMonth,
  formatDayLabel,
  isValidISODate,
  todayISO,
} from './dates';

describe('dates', () => {
  it('formats today in local time', () => {
    expect(todayISO(new Date(2026, 9, 5, 23, 59))).toBe('2026-10-05');
  });

  it('adds days across month and year boundaries', () => {
    expect(addDays('2026-10-05', -5)).toBe('2026-09-30');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29');
  });

  it('adds months with clamping and anchor day', () => {
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-28');
    expect(addMonths('2026-02-28', 1, 31)).toBe('2026-03-31');
    expect(addMonths('2026-11-15', 3)).toBe('2027-02-15');
    expect(addMonths('2026-03-15', -3)).toBe('2025-12-15');
    expect(addMonthsToKey('2026-01', -1)).toBe('2025-12');
  });

  it('knows month lengths and weekdays', () => {
    expect(daysInMonth(2028, 2)).toBe(29);
    expect(daysInMonth(2026, 2)).toBe(28);
    expect(dayOfWeek('2026-10-05')).toBe(1);
    expect(dayOfWeek('2026-10-04')).toBe(0);
  });

  it('validates ISO dates', () => {
    expect(isValidISODate('2026-02-29')).toBe(false);
    expect(isValidISODate('2028-02-29')).toBe(true);
    expect(isValidISODate('2026-13-01')).toBe(false);
    expect(isValidISODate('2026-1-01')).toBe(false);
  });

  it('labels days relative to today', () => {
    expect(formatDayLabel('2026-10-05', '2026-10-05')).toBe('今天 · 10月5日 周一');
    expect(formatDayLabel('2026-10-04', '2026-10-05')).toBe('昨天 · 10月4日 周日');
    expect(formatDayLabel('2026-10-01', '2026-10-05')).toBe('10月1日 周四');
  });
});
