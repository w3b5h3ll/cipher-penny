const DIGITS: Record<string, number> = {
  零: 0, 〇: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9,
};
const UNITS: Record<string, number> = { 十: 10, 百: 100, 千: 1000 };

export const CN_NUMERAL_CHARS = '零〇一二两三四五六七八九十百千万';

/**
 * Converts a Chinese integer numeral to a number: "三十五" -> 35, "一百零五" -> 105.
 * Supports colloquial trailing digits: "三百五" -> 350, "两万三" -> 23000.
 * Returns null for strings with unsupported characters.
 */
export function parseChineseInteger(text: string): number | null {
  if (!text) return null;
  let total = 0;
  let section = 0;
  let digit = -1;
  let lastUnit = 0;

  for (const ch of text) {
    if (ch in DIGITS) {
      digit = DIGITS[ch]!;
    } else if (ch in UNITS) {
      const unit = UNITS[ch]!;
      section += (digit === -1 ? 1 : digit) * unit;
      digit = -1;
      lastUnit = unit;
    } else if (ch === '万') {
      total += (section + Math.max(digit, 0)) * 10000;
      section = 0;
      digit = -1;
      lastUnit = 10000;
    } else {
      return null;
    }
  }

  if (digit > 0) {
    const chars = [...text];
    const colloquial = lastUnit >= 100 && isUnitChar(chars[chars.length - 2]);
    section += colloquial ? digit * (lastUnit / 10) : digit;
  }
  return total + section;
}

function isUnitChar(ch: string | undefined): boolean {
  return ch === '十' || ch === '百' || ch === '千' || ch === '万';
}
