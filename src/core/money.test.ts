import { describe, expect, it } from 'vitest';
import { centsToInput, formatCents, formatMoney, parseAmount } from './money';

describe('parseAmount (F-TX-4)', () => {
  it.each([
    ['35', 3500],
    ['35.5', 3550],
    ['35.50', 3550],
    ['0.1', 10],
    ['0.01', 1],
    ['1,234.56', 123456],
    ['¥20', 2000],
    [' 8 ', 800],
    ['12.', 1200],
  ])('%s -> %i', (input, expected) => {
    expect(parseAmount(input)).toBe(expected);
  });

  it.each(['', 'abc', '-5', '1.234', '1e5', '..1'])('rejects %j', (input) => {
    expect(parseAmount(input)).toBeNull();
  });

  it('keeps exact cents where floats would drift', () => {
    expect(parseAmount('0.1')! + parseAmount('0.2')!).toBe(parseAmount('0.3'));
  });
});

describe('formatting', () => {
  it('formats cents with grouping', () => {
    expect(formatCents(123456789)).toBe('1,234,567.89');
    expect(formatCents(5)).toBe('0.05');
    expect(formatMoney(-1050)).toBe('-¥10.50');
    expect(formatMoney(0)).toBe('¥0.00');
  });

  it('round-trips input values', () => {
    for (const c of [0, 1, 99, 3500, 3550, 123456]) {
      expect(parseAmount(centsToInput(c))).toBe(c);
    }
    expect(centsToInput(3500)).toBe('35');
    expect(centsToInput(3505)).toBe('35.05');
  });
});
