import { describe, expect, it } from 'vitest';
import fixture from '../../../fixtures/parser-cases.json';
import { createDefaultAccounts, createDefaultCategories } from '../defaults';
import { parseChineseInteger } from './chineseNumber';
import { parseEntries } from './parse';

interface ExpectedDraft {
  type: string;
  amount: number;
  category: string;
  account?: string;
  date: string;
  note: string;
}

const categories = createDefaultCategories();
const accounts = createDefaultAccounts();
const categoryName = (id: string) => categories.find((c) => c.id === id)?.name;
const accountName = (id: string | undefined) => accounts.find((a) => a.id === id)?.name;

describe('parseEntries — fixtures/parser-cases.json (F-QA-2 ~ F-QA-6)', () => {
  it.each(fixture.cases)('$name: $input', ({ input, expected }) => {
    const drafts = parseEntries(input, { today: fixture.today, categories, accounts });
    const actual: ExpectedDraft[] = drafts.map((d) => ({
      type: d.type,
      amount: d.amount,
      category: categoryName(d.categoryId) ?? '?',
      ...(d.accountId ? { account: accountName(d.accountId) ?? '?' } : {}),
      date: d.date,
      note: d.note,
    }));
    expect(actual).toEqual(expected);
  });
});

describe('parseChineseInteger', () => {
  it.each([
    ['五', 5],
    ['十', 10],
    ['十五', 15],
    ['二十', 20],
    ['三十五', 35],
    ['一百零五', 105],
    ['三百五', 350],
    ['一千二', 1200],
    ['一千二百五十', 1250],
    ['两万', 20000],
    ['两万三', 23000],
    ['一万零五百', 10500],
  ])('%s -> %i', (input, expected) => {
    expect(parseChineseInteger(input)).toBe(expected);
  });

  it('rejects non-numerals', () => {
    expect(parseChineseInteger('五块')).toBeNull();
    expect(parseChineseInteger('')).toBeNull();
  });
});
